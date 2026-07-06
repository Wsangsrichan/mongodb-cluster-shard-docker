#!/bin/bash
# ----------------------------------------------------------------------
# MongoDB Backup Service Entrypoint
#
# Runs mongodump daily at BACKUP_TIME using a while+sleep loop
# (no cron required, avoids the "cron: not found" issue).
# ----------------------------------------------------------------------

set -e

MONGO_HOST="${MONGO_HOST:-mongos-router0}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_INITDB_ROOT_USERNAME="${MONGO_INITDB_ROOT_USERNAME:-admin}"
MONGO_INITDB_ROOT_PASSWORD="${MONGO_INITDB_ROOT_PASSWORD:-changeme}"
BACKUP_TIME="${BACKUP_TIME:-01:00}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

BACKUP_DIR="/tmp/backups"
HOST_BACKUP_DIR="/host-backups"
MONGODUMP_URI="mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/admin?authSource=admin"

mkdir -p "$BACKUP_DIR"
mkdir -p "$HOST_BACKUP_DIR" 2>/dev/null || true

echo "[$(date)] Backup service started. Will run daily at ${BACKUP_TIME}"

# Track the last date we ran to avoid duplicate runs
LAST_RUN_DATE=""

while true; do
  current_time=$(date +%H:%M)
  current_date=$(date +%Y-%m-%d)

  if [ "$current_time" = "$BACKUP_TIME" ] && [ "$current_date" != "$LAST_RUN_DATE" ]; then
    echo "[$(date)] =========================================="
    echo "[$(date)] Starting scheduled backup..."

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="${BACKUP_DIR}/backup_${TIMESTAMP}"

    if mongodump \
        --uri="${MONGODUMP_URI}" \
        --out="${BACKUP_PATH}" \
        --gzip \
        2>&1; then
      echo "[$(date)] Backup completed successfully to ${BACKUP_PATH}"

      # Copy to host mount
      if [ -d "/host-backups" ]; then
        cp -r "${BACKUP_PATH}" "/host-backups/" 2>/dev/null || true
        echo "[$(date)] Backup copied to host: /host-backups/backup_${TIMESTAMP}"
      fi
    else
      echo "[$(date)] Backup FAILED!"
    fi

    # Cleanup old backups
    echo "[$(date)] Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days..."
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" -mtime "+${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true
    find "$HOST_BACKUP_DIR" -maxdepth 1 -type d -name "backup_*" -mtime "+${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true

    LAST_RUN_DATE="$current_date"
    echo "[$(date)] Backup maintenance completed"
    echo "[$(date)] =========================================="
  fi

  sleep 30
done
