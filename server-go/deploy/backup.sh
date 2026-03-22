#!/bin/bash
# Era Online — Daily Database Backup Script
#
# Backs up the SQLite database to /opt/eraonline/backups/
# and prunes backups older than 30 days.
#
# Install as a cron job (runs at 04:00 every night):
#   0 4 * * * root /opt/eraonline/backup.sh >> /opt/eraonline/logs/backup.log 2>&1
#
# Or install with setup-vps.sh, which does this automatically.

set -euo pipefail

INSTALL_DIR="/opt/eraonline"
DB_PATH="${INSTALL_DIR}/data/eraonline.db"
BACKUP_DIR="${INSTALL_DIR}/backups"
KEEP_DAYS=30
DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)
BACKUP_FILE="${BACKUP_DIR}/eraonline-${DATE}.db"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[${TIMESTAMP}] $*"; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if [[ ! -f "$DB_PATH" ]]; then
    log "ERROR: Database not found at ${DB_PATH} — nothing to back up."
    exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    log "ERROR: Backup directory ${BACKUP_DIR} does not exist."
    exit 1
fi

# ---------------------------------------------------------------------------
# Backup using SQLite's .backup command (hot backup — safe while server runs)
# This is safer than cp because SQLite's backup API handles the WAL journal.
# ---------------------------------------------------------------------------
log "Starting backup: ${DB_PATH} -> ${BACKUP_FILE}"

if command -v sqlite3 &>/dev/null; then
    # Use SQLite's online backup API via the .backup dot-command.
    # This produces a consistent snapshot even while the server is writing.
    sqlite3 "$DB_PATH" ".backup '${BACKUP_FILE}'"
else
    # Fallback: copy the file (less safe if the server is active, but
    # acceptable for SQLite with WAL mode and a short downtime risk).
    log "WARNING: sqlite3 not found — using cp fallback (consider: apt install sqlite3)"
    cp "$DB_PATH" "$BACKUP_FILE"
fi

# ---------------------------------------------------------------------------
# Verify the backup is a valid SQLite file
# ---------------------------------------------------------------------------
if command -v sqlite3 &>/dev/null; then
    if sqlite3 "$BACKUP_FILE" "PRAGMA integrity_check;" | grep -q "^ok$"; then
        log "Integrity check: OK"
    else
        log "ERROR: Backup integrity check FAILED — ${BACKUP_FILE} may be corrupt!"
        exit 1
    fi
fi

# Report backup size
BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
log "Backup complete: ${BACKUP_FILE} (${BACKUP_SIZE})"

# ---------------------------------------------------------------------------
# Set safe permissions on the backup file
# ---------------------------------------------------------------------------
chown eraonline:eraonline "$BACKUP_FILE" 2>/dev/null || true
chmod 640 "$BACKUP_FILE"

# ---------------------------------------------------------------------------
# Prune old backups (keep last KEEP_DAYS days)
# ---------------------------------------------------------------------------
DELETED=0
while IFS= read -r old_backup; do
    rm -f "$old_backup"
    log "Deleted old backup: $(basename "$old_backup")"
    ((DELETED++)) || true
done < <(find "$BACKUP_DIR" -name "eraonline-*.db" -mtime +${KEEP_DAYS} -type f 2>/dev/null | sort)

REMAINING=$(find "$BACKUP_DIR" -name "eraonline-*.db" -type f 2>/dev/null | wc -l)
log "Pruned ${DELETED} old backup(s). ${REMAINING} backup(s) retained."
