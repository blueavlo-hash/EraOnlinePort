#!/bin/bash
# Era Online Server — Build & Deploy Pipeline
#
# Builds the Go server locally (Linux amd64 static binary), uploads it to the
# VPS, and performs a safe rolling restart with automatic rollback on failure.
#
# Usage:
#   ./deploy/build-and-deploy.sh user@vps-ip
#   ./deploy/build-and-deploy.sh root@203.0.113.10
#
# Requirements (local machine):
#   - Go installed (go build)
#   - ssh / scp in PATH
#   - SSH key-based auth to the VPS (no password prompts)
#
# Environment variables (all optional):
#   SSH_KEY       Path to SSH private key (default: ~/.ssh/id_rsa)
#   SSH_PORT      SSH port on the VPS (default: 22)
#   SKIP_TESTS    Set to "1" to skip 'go test' before building

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 user@vps-ip"
    echo ""
    echo "Examples:"
    echo "  $0 root@203.0.113.10"
    echo "  SSH_KEY=~/.ssh/vps_key $0 deploy@my-server.example.com"
    exit 1
fi

VPS_TARGET="$1"               # user@ip
INSTALL_DIR="/opt/eraonline"
BINARY_NAME="eraonline-server"
LINUX_BINARY="${BINARY_NAME}-linux-amd64"

SSH_KEY="${SSH_KEY:-}"
SSH_PORT="${SSH_PORT:-22}"
SKIP_TESTS="${SKIP_TESTS:-0}"

# Build SSH/SCP option strings
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi
SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
if [[ -n "$SSH_KEY" ]]; then
    SCP_OPTS+=(-i "$SSH_KEY")
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo -e "\033[0;32m[BUILD]\033[0m $*"; }
remote()  { echo -e "\033[0;36m[REMOTE]\033[0m $*"; }
warn()    { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()     { echo -e "\033[0;31m[FAIL]\033[0m  $*" >&2; exit 1; }

run_remote() {
    # Run a command on the VPS and prefix output with [REMOTE]
    ssh "${SSH_OPTS[@]}" "$VPS_TARGET" "$@"
}

# Move to the repo root (one level above this script's directory)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 1. Pre-flight checks
# ---------------------------------------------------------------------------
info "Pre-flight checks..."
command -v go  &>/dev/null || die "go not found in PATH"
command -v ssh &>/dev/null || die "ssh not found in PATH"
command -v scp &>/dev/null || die "scp not found in PATH"

# Verify we can reach the VPS before spending time building
info "Testing SSH connectivity to ${VPS_TARGET}..."
run_remote "echo 'SSH OK'" || die "Cannot SSH to ${VPS_TARGET}. Check your key/IP/port."

# ---------------------------------------------------------------------------
# 2. Run tests
# ---------------------------------------------------------------------------
if [[ "$SKIP_TESTS" != "1" ]]; then
    info "Running tests..."
    go test ./... || die "Tests failed — aborting deploy. Set SKIP_TESTS=1 to override."
else
    warn "Tests skipped (SKIP_TESTS=1)."
fi

# ---------------------------------------------------------------------------
# 3. Build Linux static binary
# ---------------------------------------------------------------------------
VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
info "Building ${LINUX_BINARY}  (version=${VERSION}  built=${BUILD_TIME})"

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -ldflags "-s -w -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME}" \
    -o "${LINUX_BINARY}" \
    ./cmd/server

BINARY_SIZE=$(du -sh "${LINUX_BINARY}" | cut -f1)
info "Binary built: ${LINUX_BINARY} (${BINARY_SIZE})"

# ---------------------------------------------------------------------------
# 4. Create deploy tarball
#    Contents: binary + config template (never overwrites live config)
# ---------------------------------------------------------------------------
DEPLOY_ARCHIVE="eraonline-deploy-${VERSION}.tar.gz"
info "Creating deploy archive: ${DEPLOY_ARCHIVE}"

tar -czf "${DEPLOY_ARCHIVE}" \
    "${LINUX_BINARY}" \
    "config/server.yaml" \
    "deploy/backup.sh" \
    "deploy/health-check.sh" \
    "deploy/eraonline-server.service"

info "Archive created ($(du -sh "${DEPLOY_ARCHIVE}" | cut -f1))"

# ---------------------------------------------------------------------------
# 5. Upload to VPS
# ---------------------------------------------------------------------------
info "Uploading deploy archive to ${VPS_TARGET}:${INSTALL_DIR}/..."
scp "${SCP_OPTS[@]}" "${DEPLOY_ARCHIVE}" "${VPS_TARGET}:/tmp/${DEPLOY_ARCHIVE}"
info "Upload complete."

# ---------------------------------------------------------------------------
# 6. Remote update sequence
# ---------------------------------------------------------------------------
remote "Running update sequence on VPS..."

run_remote bash -s -- "${INSTALL_DIR}" "${BINARY_NAME}" "${LINUX_BINARY}" "${DEPLOY_ARCHIVE}" << 'REMOTE_SCRIPT'
set -euo pipefail

INSTALL_DIR="$1"
BINARY_NAME="$2"
LINUX_BINARY="$3"
DEPLOY_ARCHIVE="$4"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "[remote] Extracting deploy archive..."
cd /tmp
tar -xzf "${DEPLOY_ARCHIVE}"

# --- Stop service ---
echo "[remote] Stopping ${BINARY_NAME} service..."
if systemctl is-active --quiet eraonline-server; then
    systemctl stop eraonline-server
    echo "[remote] Service stopped."
else
    echo "[remote] Service was not running."
fi

# --- Back up old binary ---
if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    BACKUP_PATH="${INSTALL_DIR}/backups/${BINARY_NAME}-${TIMESTAMP}"
    cp "${INSTALL_DIR}/${BINARY_NAME}" "${BACKUP_PATH}"
    echo "[remote] Old binary backed up to ${BACKUP_PATH}"
    # Keep only last 5 binary backups
    ls -t "${INSTALL_DIR}/backups/${BINARY_NAME}-"* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
fi

# --- Install new binary ---
install -m 755 -o eraonline -g eraonline "/tmp/${LINUX_BINARY}" "${INSTALL_DIR}/${BINARY_NAME}"
echo "[remote] New binary installed."

# --- Install updated helper scripts ---
install -m 750 -o root -g root "/tmp/deploy/backup.sh"       "${INSTALL_DIR}/backup.sh"       2>/dev/null || true
install -m 755 -o root -g root "/tmp/deploy/health-check.sh" "${INSTALL_DIR}/health-check.sh" 2>/dev/null || true

# --- Update systemd service if it changed ---
install -m 644 "/tmp/deploy/eraonline-server.service" /etc/systemd/system/eraonline-server.service
systemctl daemon-reload

# --- Install config template (never overwrite live config) ---
if [[ ! -f "${INSTALL_DIR}/config/server.yaml" ]]; then
    install -m 640 -o eraonline -g eraonline "/tmp/config/server.yaml" "${INSTALL_DIR}/config/server.yaml"
    echo "[remote] Config template installed (first deploy)."
    echo "[remote] WARNING: Edit ${INSTALL_DIR}/config/server.yaml and change the secrets!"
else
    install -m 640 -o eraonline -g eraonline "/tmp/config/server.yaml" "${INSTALL_DIR}/config/server.yaml.example"
    echo "[remote] Config template saved as server.yaml.example (existing config preserved)."
fi

# --- Start service ---
echo "[remote] Starting eraonline-server..."
systemctl start eraonline-server

# --- Health check (give the server 3 seconds to start) ---
sleep 3
if systemctl is-active --quiet eraonline-server; then
    echo "[remote] Service is running."
else
    echo "[remote] ERROR: Service failed to start! Rolling back..."
    systemctl stop eraonline-server 2>/dev/null || true
    if [[ -f "${BACKUP_PATH}" ]]; then
        install -m 755 -o eraonline -g eraonline "${BACKUP_PATH}" "${INSTALL_DIR}/${BINARY_NAME}"
        systemctl start eraonline-server
        echo "[remote] Rollback complete. Old binary restored."
    fi
    exit 1
fi

# --- Clean up ---
rm -f "/tmp/${DEPLOY_ARCHIVE}" "/tmp/${LINUX_BINARY}"
rm -rf /tmp/deploy /tmp/config

echo ""
echo "[remote] === Last 20 lines of server log ==="
tail -n 20 "${INSTALL_DIR}/logs/server.log" 2>/dev/null || echo "(log file not yet written — check: journalctl -u eraonline-server)"
REMOTE_SCRIPT

# ---------------------------------------------------------------------------
# 7. Final status
# ---------------------------------------------------------------------------
echo ""
info "=== Deploy complete ==="
echo ""
echo "  Version deployed : ${VERSION}"
echo "  Target           : ${VPS_TARGET}"
echo ""
echo "  Useful commands:"
echo "    Tail logs   : ssh ${VPS_TARGET} 'tail -f ${INSTALL_DIR}/logs/server.log'"
echo "    Error log   : ssh ${VPS_TARGET} 'tail -f ${INSTALL_DIR}/logs/error.log'"
echo "    Service     : ssh ${VPS_TARGET} 'systemctl status eraonline-server'"
echo "    Health check: ssh ${VPS_TARGET} '${INSTALL_DIR}/health-check.sh'"
echo ""

# Clean up local archive
rm -f "${DEPLOY_ARCHIVE}"
