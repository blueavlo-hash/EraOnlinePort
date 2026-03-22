#!/bin/bash
# Era Online Server — VPS Setup Script
# Run as root on a fresh Ubuntu 22.04 LTS VPS.
# Usage: bash setup-vps.sh
#
# What this script does:
#   - Updates system packages and installs security tools
#   - Creates a dedicated non-login system user (eraonline)
#   - Creates the install directory tree under /opt/eraonline
#   - Hardens the firewall with UFW (allows SSH + game ports only)
#   - Configures fail2ban to block SSH brute-force attempts
#   - Installs Go 1.22 for building on the server (optional but useful)
#   - Sets up log rotation for application logs
#   - Enables automatic security updates
#   - Installs the systemd service unit

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — adjust if needed
# ---------------------------------------------------------------------------
GO_VERSION="1.22.4"
GO_CHECKSUM="ba79d4526102575196273416239cca418a651e049c2b099f3159db85e7bade7d"  # sha256 of linux-amd64 tarball
SERVER_USER="eraonline"
INSTALL_DIR="/opt/eraonline"
GAME_PORT="6969"
HTTP_API_PORT="6970"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\033[0;32m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
require_root

echo ""
echo "============================================================"
echo "  Era Online — VPS Setup  (Ubuntu 22.04 LTS)"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. System update
# ---------------------------------------------------------------------------
info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq

# ---------------------------------------------------------------------------
# 2. Install required packages
# ---------------------------------------------------------------------------
info "Installing required packages..."
apt-get install -y -qq \
    ufw \
    fail2ban \
    logrotate \
    curl \
    wget \
    unzip \
    netcat-openbsd \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential \
    git \
    sqlite3 \
    unattended-upgrades \
    apt-listchanges

# ---------------------------------------------------------------------------
# 3. Configure automatic security updates
# ---------------------------------------------------------------------------
info "Configuring automatic security updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# ---------------------------------------------------------------------------
# 4. Create dedicated system user
# ---------------------------------------------------------------------------
info "Creating system user '${SERVER_USER}'..."
if ! id "$SERVER_USER" &>/dev/null; then
    useradd \
        --system \
        --shell /bin/false \
        --home-dir "$INSTALL_DIR" \
        --create-home \
        "$SERVER_USER"
    info "User '${SERVER_USER}' created."
else
    warn "User '${SERVER_USER}' already exists — skipping."
fi

# ---------------------------------------------------------------------------
# 5. Create directory structure
# ---------------------------------------------------------------------------
info "Creating install directory tree at ${INSTALL_DIR}..."
mkdir -p \
    "${INSTALL_DIR}/config" \
    "${INSTALL_DIR}/data" \
    "${INSTALL_DIR}/logs" \
    "${INSTALL_DIR}/backups"

# config and data should not be world-readable
chmod 750 "${INSTALL_DIR}/config"
chmod 750 "${INSTALL_DIR}/data"
chmod 750 "${INSTALL_DIR}/backups"
chmod 755 "${INSTALL_DIR}/logs"

chown -R "${SERVER_USER}:${SERVER_USER}" "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# 6. UFW firewall
# ---------------------------------------------------------------------------
info "Configuring UFW firewall..."

# Ensure ufw is available
if ! command -v ufw &>/dev/null; then
    error "ufw not found after install — aborting."
    exit 1
fi

# Default policies
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (must come before enable, or you lock yourself out)
ufw allow ssh comment "SSH administration"

# Era Online ports
ufw allow "${GAME_PORT}/tcp"    comment "EraOnline game (binary TLS protocol)"
ufw allow "${HTTP_API_PORT}/tcp" comment "EraOnline HTTP API"

# Enable without interactive prompt
ufw --force enable

info "UFW status:"
ufw status verbose

# ---------------------------------------------------------------------------
# 7. fail2ban — SSH protection
# ---------------------------------------------------------------------------
info "Configuring fail2ban..."

# Write a clean jail.local that only overrides what we need
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
# Ban for 1 hour after 5 failures in a 10-minute window
bantime  = 3600
findtime = 600
maxretry = 5
# Use systemd backend on Ubuntu 22.04
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 5
EOF

systemctl enable fail2ban
systemctl restart fail2ban
info "fail2ban started."

# ---------------------------------------------------------------------------
# 8. Install Go ${GO_VERSION}
# ---------------------------------------------------------------------------
if command -v go &>/dev/null; then
    INSTALLED_GO=$(go version | awk '{print $3}' | sed 's/go//')
    info "Go ${INSTALLED_GO} already installed — skipping."
else
    info "Downloading Go ${GO_VERSION}..."
    GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
    curl -fsSL "https://go.dev/dl/${GO_TARBALL}" -o "/tmp/${GO_TARBALL}"

    # Verify checksum
    ACTUAL_SUM=$(sha256sum "/tmp/${GO_TARBALL}" | awk '{print $1}')
    if [[ "$ACTUAL_SUM" != "$GO_CHECKSUM" ]]; then
        error "Go tarball checksum mismatch!"
        error "  Expected: ${GO_CHECKSUM}"
        error "  Actual:   ${ACTUAL_SUM}"
        rm -f "/tmp/${GO_TARBALL}"
        exit 1
    fi
    info "Checksum verified."

    rm -rf /usr/local/go
    tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
    rm -f "/tmp/${GO_TARBALL}"

    # Make go available system-wide
    ln -sf /usr/local/go/bin/go   /usr/local/bin/go
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
fi

go version

# ---------------------------------------------------------------------------
# 9. Log rotation
# ---------------------------------------------------------------------------
info "Configuring log rotation for application logs..."
cat > /etc/logrotate.d/eraonline <<EOF
${INSTALL_DIR}/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 ${SERVER_USER} ${SERVER_USER}
    sharedscripts
    postrotate
        # Signal the server to reopen log files (it uses append mode, so a
        # simple restart is the safest approach if HUP is not implemented)
        systemctl kill --signal=HUP eraonline-server 2>/dev/null || true
    endscript
}
EOF

# ---------------------------------------------------------------------------
# 10. Install backup cron job
# ---------------------------------------------------------------------------
info "Installing daily backup cron job..."
if [[ -f "${SCRIPT_DIR}/backup.sh" ]]; then
    install -m 750 -o root -g root "${SCRIPT_DIR}/backup.sh" "${INSTALL_DIR}/backup.sh"
    # Install cron entry for 04:00 daily, run as root (script drops to eraonline paths)
    CRON_LINE="0 4 * * * root ${INSTALL_DIR}/backup.sh >> ${INSTALL_DIR}/logs/backup.log 2>&1"
    CRON_FILE="/etc/cron.d/eraonline-backup"
    echo "$CRON_LINE" > "$CRON_FILE"
    chmod 644 "$CRON_FILE"
    info "Backup cron installed: ${CRON_FILE}"
else
    warn "backup.sh not found next to setup-vps.sh — skipping cron install."
    warn "Copy deploy/backup.sh to ${INSTALL_DIR}/backup.sh and add a cron entry manually."
fi

# ---------------------------------------------------------------------------
# 11. Install health-check script
# ---------------------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/health-check.sh" ]]; then
    install -m 755 -o root -g root "${SCRIPT_DIR}/health-check.sh" "${INSTALL_DIR}/health-check.sh"
    info "health-check.sh installed at ${INSTALL_DIR}/health-check.sh"
fi

# ---------------------------------------------------------------------------
# 12. Install systemd service
# ---------------------------------------------------------------------------
info "Installing systemd service..."
if [[ -f "${SCRIPT_DIR}/eraonline-server.service" ]]; then
    install -m 644 "${SCRIPT_DIR}/eraonline-server.service" /etc/systemd/system/eraonline-server.service
    systemctl daemon-reload
    systemctl enable eraonline-server
    info "Service installed and enabled (not started — configure first)."
else
    error "eraonline-server.service not found at ${SCRIPT_DIR}/"
    exit 1
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  Setup complete!"
echo "============================================================"
echo ""
echo "NEXT STEPS:"
echo ""
echo "  1. Deploy the server binary (from your local machine):"
echo "       make build-linux"
echo "       ./deploy/build-and-deploy.sh root@<VPS_IP>"
echo ""
echo "  2. Edit the config file on the VPS:"
echo "       nano ${INSTALL_DIR}/config/server.yaml"
echo "     IMPORTANT: change server.secret and server.client_identity_secret"
echo ""
echo "  3. Copy game data to the VPS:"
echo "       scp -r EraOnline/data/ root@<VPS_IP>:${INSTALL_DIR}/data/"
echo "       ssh root@<VPS_IP> chown -R eraonline:eraonline ${INSTALL_DIR}/data"
echo ""
echo "  4. Start the server:"
echo "       systemctl start eraonline-server"
echo "       systemctl status eraonline-server"
echo ""
echo "  5. Watch logs:"
echo "       tail -f ${INSTALL_DIR}/logs/server.log"
echo "       journalctl -u eraonline-server -f"
echo ""
echo "  See deploy/README.md for the full deployment guide."
echo ""
