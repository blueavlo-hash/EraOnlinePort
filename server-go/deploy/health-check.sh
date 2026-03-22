#!/bin/bash
# Era Online — Health Check Script
#
# Checks whether the server is alive and accepting connections.
# Exit code:  0 = fully healthy
#             1 = one or more checks failed
#
# Usage:
#   /opt/eraonline/health-check.sh           # full check, human output
#   /opt/eraonline/health-check.sh --json    # JSON output (for monitoring APIs)
#   /opt/eraonline/health-check.sh --quiet   # no output, exit code only
#
# Suitable for:
#   - Uptime Robot "Custom HTTP" monitor (point at http://localhost:6970/status)
#   - Cron-based alerting
#   - Docker/Kubernetes liveness probe

set -uo pipefail

INSTALL_DIR="/opt/eraonline"
GAME_PORT="6969"
HTTP_PORT="6970"
STATUS_URL="http://127.0.0.1:${HTTP_PORT}/status"
TIMEOUT=5   # seconds for HTTP/TCP checks

# Parse flags
OUTPUT_JSON=0
QUIET=0
for arg in "$@"; do
    case "$arg" in
        --json)  OUTPUT_JSON=1 ;;
        --quiet) QUIET=1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

# Check 1: systemd service state
check_service() {
    if systemctl is-active --quiet eraonline-server 2>/dev/null; then
        echo "ok"
    else
        local state
        state=$(systemctl is-active eraonline-server 2>/dev/null || echo "unknown")
        echo "failed (state=${state})"
    fi
}

# Check 2: HTTP status endpoint
check_http() {
    if ! command -v curl &>/dev/null; then
        echo "skip (curl not installed)"
        return
    fi
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TIMEOUT" \
        --connect-timeout "$TIMEOUT" \
        "$STATUS_URL" 2>/dev/null) || http_code="000"

    if [[ "$http_code" == "200" ]]; then
        echo "ok (HTTP ${http_code})"
    else
        echo "failed (HTTP ${http_code})"
    fi
}

# Check 3: Game TCP port accepting connections
check_game_port() {
    if ! command -v nc &>/dev/null; then
        echo "skip (nc not installed)"
        return
    fi
    if nc -z -w "$TIMEOUT" 127.0.0.1 "$GAME_PORT" 2>/dev/null; then
        echo "ok (port ${GAME_PORT} open)"
    else
        echo "failed (port ${GAME_PORT} not accepting connections)"
    fi
}

# Check 4: Disk space — warn if logs/data volume is >90% full
check_disk() {
    local usage
    usage=$(df -P "${INSTALL_DIR}" 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}')
    if [[ -z "$usage" ]]; then
        echo "skip (could not read disk usage)"
        return
    fi
    if [[ "$usage" -lt 90 ]]; then
        echo "ok (${usage}% used)"
    else
        echo "warning (${usage}% used — low disk space!)"
    fi
}

# Check 5: Memory — warn if systemd says MemoryCurrent is >450M
check_memory() {
    if ! systemctl show eraonline-server --property=MemoryCurrent &>/dev/null; then
        echo "skip"
        return
    fi
    local mem_bytes
    mem_bytes=$(systemctl show eraonline-server --property=MemoryCurrent 2>/dev/null \
        | cut -d= -f2)
    if [[ "$mem_bytes" == "[not set]" ]] || [[ -z "$mem_bytes" ]]; then
        echo "skip"
        return
    fi
    local mem_mb=$(( mem_bytes / 1024 / 1024 ))
    if [[ "$mem_mb" -lt 450 ]]; then
        echo "ok (${mem_mb} MB)"
    else
        echo "warning (${mem_mb} MB — approaching MemoryMax limit)"
    fi
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
SVC=$(check_service)
HTTP=$(check_http)
PORT=$(check_game_port)
DISK=$(check_disk)
MEM=$(check_memory)

# Determine overall health
HEALTHY=1
[[ "$SVC"  == ok* ]] || HEALTHY=0
[[ "$HTTP" == ok* ]] || [[ "$HTTP" == skip* ]] || HEALTHY=0
[[ "$PORT" == ok* ]] || [[ "$PORT" == skip* ]] || HEALTHY=0
# Disk/memory warnings don't flip HEALTHY but are reported

OVERALL="HEALTHY"
[[ $HEALTHY -eq 1 ]] || OVERALL="UNHEALTHY"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ $QUIET -eq 1 ]]; then
    exit $((1 - HEALTHY))
fi

if [[ $OUTPUT_JSON -eq 1 ]]; then
    cat <<EOF
{
  "status": "${OVERALL}",
  "checks": {
    "service":   "${SVC}",
    "http_api":  "${HTTP}",
    "game_port": "${PORT}",
    "disk":      "${DISK}",
    "memory":    "${MEM}"
  },
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
else
    echo "Era Online Health Check — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "---------------------------------------------------"
    printf "  %-20s %s\n" "Service (systemd):" "$SVC"
    printf "  %-20s %s\n" "HTTP API (:${HTTP_PORT}):" "$HTTP"
    printf "  %-20s %s\n" "Game port (:${GAME_PORT}):" "$PORT"
    printf "  %-20s %s\n" "Disk space:" "$DISK"
    printf "  %-20s %s\n" "Memory:" "$MEM"
    echo "---------------------------------------------------"
    echo "  Overall: ${OVERALL}"
fi

exit $((1 - HEALTHY))
