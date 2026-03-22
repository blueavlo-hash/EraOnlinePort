# Era Online — Production Deployment Guide

This guide walks through deploying the Era Online Go server to a Linux VPS.
The entire process takes about 15 minutes on a fresh Ubuntu 22.04 server.

---

## Contents

1. [Prerequisites](#1-prerequisites)
2. [First-time VPS Setup](#2-first-time-vps-setup)
3. [Configure the Server](#3-configure-the-server)
4. [Upload Game Data](#4-upload-game-data)
5. [Build and Deploy the Binary](#5-build-and-deploy-the-binary)
6. [Configure the Game Client](#6-configure-the-game-client)
7. [Verify the Deployment](#7-verify-the-deployment)
8. [Ongoing Operations](#8-ongoing-operations)
9. [Zero-Downtime Updates](#9-zero-downtime-updates)
10. [Troubleshooting](#10-troubleshooting)
11. [Security Notes](#11-security-notes)

---

## 1. Prerequisites

### VPS Requirements (minimum)
| Resource  | Minimum        | Recommended       |
|-----------|---------------|-------------------|
| CPU       | 1 vCPU        | 2 vCPU            |
| RAM       | 1 GB          | 2 GB              |
| Disk      | 10 GB SSD     | 20 GB SSD         |
| OS        | Ubuntu 22.04  | Ubuntu 22.04 LTS  |
| Network   | 100 Mbps      | 1 Gbps            |

Typical providers: DigitalOcean, Vultr, Linode, Hetzner Cloud.
A $6/month droplet (1 vCPU / 1 GB RAM) handles 100–200 simultaneous players comfortably.

### Local Machine Requirements
- Go 1.22+ installed (`go version`)
- `ssh` and `scp` in PATH
- SSH key-based authentication set up to the VPS (no password prompts)

### SSH Key Setup (if needed)
```bash
# Generate a key (if you don't have one)
ssh-keygen -t ed25519 -C "eraonline-deploy"

# Copy it to the VPS
ssh-copy-id root@YOUR_VPS_IP
```

---

## 2. First-time VPS Setup

Run the setup script once on a **fresh** Ubuntu 22.04 VPS as root:

```bash
# From the server-go directory on your local machine:
scp -r deploy/ root@YOUR_VPS_IP:/tmp/eo3-deploy/
ssh root@YOUR_VPS_IP "bash /tmp/eo3-deploy/setup-vps.sh"
```

What the setup script does:
- Updates all system packages
- Installs: ufw, fail2ban, logrotate, sqlite3, Go 1.22, curl, wget
- Creates the `eraonline` system user (no shell, no login)
- Creates directory tree: `/opt/eraonline/{config,data,logs,backups}`
- Configures UFW (blocks everything except SSH, port 6969, port 6970)
- Configures fail2ban (bans IPs with 5 failed SSH logins for 1 hour)
- Installs automatic security updates (unattended-upgrades)
- Sets up log rotation for `/opt/eraonline/logs/*.log`
- Installs the systemd service unit
- Installs `backup.sh` and a daily cron job (04:00 UTC)

The server **will not start** yet — you must configure it first (step 3).

---

## 3. Configure the Server

After setup, edit the config file on the VPS:

```bash
ssh root@YOUR_VPS_IP "nano /opt/eraonline/config/server.yaml"
```

**Required changes** (the server refuses to start with the default placeholder values):

```yaml
server:
  secret: "generate-with-openssl-rand-hex-32"
  client_identity_secret: "generate-with-openssl-rand-hex-16"

game:
  game_data_dir: /opt/eraonline/data
```

Generate safe secrets:
```bash
openssl rand -hex 32    # for server.secret
openssl rand -hex 16    # for client_identity_secret
```

**Important**: the `client_identity_secret` value must match the constant
`CLIENT_IDENTITY_SECRET` in the Godot client's `scripts/autoloads/Network.gd`.
Update both at the same time, or clients will be rejected.

Set secure permissions on the config:
```bash
ssh root@YOUR_VPS_IP "chmod 640 /opt/eraonline/config/server.yaml && chown eraonline:eraonline /opt/eraonline/config/server.yaml"
```

---

## 4. Upload Game Data

The server needs the JSON game data files produced by the Python pipeline
(maps, NPCs, objects, spells, GRH index). These are the files in
`EraOnline/data/` of the Godot project.

```bash
# From the eo3 root directory (C:/eo3 on Windows):
scp -r EraOnline/data/ root@YOUR_VPS_IP:/opt/eraonline/data/

# Fix ownership
ssh root@YOUR_VPS_IP "chown -R eraonline:eraonline /opt/eraonline/data"
```

Expected structure on the VPS after upload:
```
/opt/eraonline/data/
├── maps/
│   ├── map_1.json
│   └── map_N.json
├── npcs.json
├── objects.json
├── spells.json
└── grh.json
```

Note: The SQLite database (`eraonline.db`) is created automatically in
`/opt/eraonline/data/` on first server start. Do not upload it.

---

## 5. Build and Deploy the Binary

From your local machine (the `server-go` directory):

```bash
./deploy/build-and-deploy.sh root@YOUR_VPS_IP
```

The script will:
1. Run `go test ./...` (skip with `SKIP_TESTS=1`)
2. Cross-compile a static Linux amd64 binary
3. Create a deploy tarball
4. Upload it to the VPS via SCP
5. Stop the running server
6. Back up the old binary
7. Install the new binary
8. Start the server
9. Verify the service is running
10. Print the last 20 lines of the server log
11. Automatically roll back to the previous binary if startup fails

On first deploy the server will start and:
- Generate a self-signed TLS certificate (stored in `/opt/eraonline/data/`)
- Create the SQLite database
- Log startup messages to `/opt/eraonline/logs/server.log`

---

## 6. Configure the Game Client

In the Godot client (`scripts/autoloads/Network.gd`), update the server address:

```gdscript
const DEFAULT_SERVER_IP   = "YOUR_VPS_IP"
const DEFAULT_SERVER_PORT = 6969
const CLIENT_IDENTITY_SECRET = "your-client-identity-secret"  # must match server.yaml
```

Rebuild the Godot client export and distribute to players.

To allow players to enter the server address manually in the splash screen,
no code change is needed — the Splash UI already has an address field.

---

## 7. Verify the Deployment

### Check the service is running
```bash
ssh root@YOUR_VPS_IP "systemctl status eraonline-server"
```

### Check the HTTP status endpoint
```bash
curl http://YOUR_VPS_IP:6970/status
```
Expected response: `{"status":"ok", ...}`

### Run the full health check
```bash
ssh root@YOUR_VPS_IP "/opt/eraonline/health-check.sh"
```

### Test the game port is accepting TCP connections
```bash
nc -z -w5 YOUR_VPS_IP 6969 && echo "Game port open" || echo "Game port closed"
```

### Watch the server log live
```bash
ssh root@YOUR_VPS_IP "tail -f /opt/eraonline/logs/server.log"
```

---

## 8. Ongoing Operations

### Read logs
```bash
# Application log (info/debug output from the server)
ssh root@YOUR_VPS_IP "tail -f /opt/eraonline/logs/server.log"

# Error log (warnings and errors only)
ssh root@YOUR_VPS_IP "tail -f /opt/eraonline/logs/error.log"

# Via systemd journal (same data, different interface)
ssh root@YOUR_VPS_IP "journalctl -u eraonline-server -f"

# Last 100 lines with timestamps
ssh root@YOUR_VPS_IP "journalctl -u eraonline-server -n 100 --no-pager"
```

### Restart the server
```bash
ssh root@YOUR_VPS_IP "systemctl restart eraonline-server"
```

### Stop and disable the server
```bash
ssh root@YOUR_VPS_IP "systemctl stop eraonline-server"
ssh root@YOUR_VPS_IP "systemctl disable eraonline-server"  # don't auto-start on boot
```

### Manual database backup
```bash
ssh root@YOUR_VPS_IP "/opt/eraonline/backup.sh"
```

Backups are stored in `/opt/eraonline/backups/eraonline-YYYY-MM-DD.db`.
The automatic cron job runs daily at 04:00 UTC and keeps the last 30 backups.

### Check backup history
```bash
ssh root@YOUR_VPS_IP "ls -lh /opt/eraonline/backups/"
```

### Monitor resource usage
```bash
ssh root@YOUR_VPS_IP "systemctl status eraonline-server"   # shows memory/CPU
ssh root@YOUR_VPS_IP "df -h /opt/eraonline"                # disk usage
```

---

## 9. Zero-Downtime Updates

The deploy script handles rolling updates automatically:

```bash
./deploy/build-and-deploy.sh root@YOUR_VPS_IP
```

The update sequence:
1. New binary uploaded to `/tmp` on VPS
2. Server stopped gracefully (players are disconnected — brief outage)
3. Old binary backed up to `/opt/eraonline/backups/eraonline-server-TIMESTAMP`
4. New binary installed
5. Server started
6. If the server fails to start within 3 seconds → old binary is restored automatically

**Note on "zero-downtime"**: True zero-downtime (hot reload) is not currently
implemented. Typical restart time is under 2 seconds. Players will see a brief
disconnect and can immediately reconnect. Schedule updates during off-peak hours
to minimise disruption.

To roll back manually to a specific previous binary:
```bash
ssh root@YOUR_VPS_IP "
  systemctl stop eraonline-server
  ls /opt/eraonline/backups/eraonline-server-*
  # pick the one you want:
  cp /opt/eraonline/backups/eraonline-server-20260315-0200 /opt/eraonline/eraonline-server
  systemctl start eraonline-server
"
```

---

## 10. Troubleshooting

### Server fails to start
```bash
# Check the full startup log
ssh root@YOUR_VPS_IP "journalctl -u eraonline-server --no-pager -n 50"
ssh root@YOUR_VPS_IP "cat /opt/eraonline/logs/error.log"
```

Common causes:
- **"CHANGE_ME" secrets**: Edit `server.yaml` and set real secrets
- **game_data_dir not found**: Ensure you uploaded game data (step 4) and the path in server.yaml is correct
- **Port already in use**: `ss -tlnp | grep -E '6969|6970'` — another process on the port
- **Permission denied on database**: `chown -R eraonline:eraonline /opt/eraonline/data`

### Players can't connect
1. Check the server is running: `systemctl status eraonline-server`
2. Check UFW allows the port: `ufw status`
3. Check the VPS provider's external firewall (separate from UFW — check the control panel)
4. Verify the client is pointing at the right IP and port 6969
5. Test TCP reachability: `nc -z -w5 YOUR_VPS_IP 6969`

### fail2ban blocked your own IP
```bash
ssh root@YOUR_VPS_IP "fail2ban-client status sshd"
ssh root@YOUR_VPS_IP "fail2ban-client set sshd unbanip YOUR_IP"
```

### Disk space filling up
```bash
ssh root@YOUR_VPS_IP "du -sh /opt/eraonline/*"
```
- Logs: check `/opt/eraonline/logs/` — logrotate runs daily and keeps 14 days
- Backups: `ls /opt/eraonline/backups/` — kept for 30 days automatically
- Database: if `eraonline.db` is huge, run `sqlite3 eraonline.db VACUUM` during off-peak hours

### High memory usage
The MemoryMax in the systemd service is 512 MB. If the server is killed by the
OOM killer, increase it:
```bash
ssh root@YOUR_VPS_IP "systemctl edit eraonline-server"
# Add:
# [Service]
# MemoryMax=1G
systemctl daemon-reload && systemctl restart eraonline-server
```

### TLS certificate expired (self-signed, 1 year)
Delete the auto-generated cert and restart — the server will generate a new one:
```bash
ssh root@YOUR_VPS_IP "
  systemctl stop eraonline-server
  rm /opt/eraonline/data/tls-cert.pem /opt/eraonline/data/tls-key.pem
  systemctl start eraonline-server
"
```

---

## 11. Security Notes

### Port summary
| Port | Protocol | Accessible from | Purpose |
|------|----------|-----------------|---------|
| 22   | TCP      | Your IP only (ideally) | SSH administration |
| 6969 | TCP      | Internet | Game binary protocol (TLS encrypted) |
| 6970 | TCP      | Internet | HTTP API (plain HTTP — no credentials travel here) |
| 6971 | TCP      | 127.0.0.1 only | Admin API (disabled by default) |

### Why is the HTTP API (6970) plain HTTP?
Player credentials (passwords) are only ever sent over the game port (6969),
which uses TLS. The HTTP API on 6970 is used for:
- Account registration (password is hashed client-side before sending, or
  alternatively registration can be moved to the TLS port)
- The `/status` endpoint (no sensitive data)

If you add an endpoint to 6970 that handles sensitive data, put nginx in front
with TLS (see `deploy/nginx.conf`).

### Restricting SSH access
After setup, consider limiting SSH to your own IP in UFW:
```bash
ufw delete allow ssh
ufw allow from YOUR_HOME_IP to any port 22
```

### The client_identity_secret
This is a shared secret baked into the client binary. It provides a basic
barrier against random bots and scanners but is NOT a cryptographic guarantee —
anyone who decompiles the client can extract it. Its purpose is to reduce
log noise and wasted server resources, not to prevent determined attackers.

### Secrets rotation
If you need to rotate `server.secret`:
1. Update `server.yaml` with the new value
2. All active sessions will be invalidated (players are disconnected)
3. Restart the server
4. No database migration needed (sessions are in-memory only)
