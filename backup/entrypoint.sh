#!/bin/bash
# ----------------------------------------------------------------------
# MongoDB Backup Service Entrypoint
#
# Sets up a cron job to run mongodump daily at BACKUP_TIME,
# cleans up old backups, and copies to host-backups directory.
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

# Create the backup script
cat > /usr/local/bin/backup.sh << 'SCRIPTEOF'
#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="/tmp/backups/backup_${TIMESTAMP}"
HOST_BACKUP_PATH="/host-backups/backup_${TIMESTAMP}"

echo "[$(date)] Starting mongodump backup..."

mongodump \
    --uri="${MONGODUMP_URI}" \
    --out="${BACKUP_PATH}" \
    --gzip \
    2>&1

if [ $? -eq 0 ]; then
    echo "[$(date)] Backup completed successfully to ${BACKUP_PATH}"

    # Copy to host mount
    if [ -d "/host-backups" ]; then
        cp -r "${BACKUP_PATH}" "/host-backups/" 2>/dev/null || true
        echo "[$(date)] Backup copied to host: /host-backups/backup_${TIMESTAMP}"
    fi
else
    echo "[$(date)] Backup FAILED!"
    exit 1
fi

# Cleanup old backups
echo "[$(date)] Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days..."
find /tmp/backups -maxdepth 1 -type d -name "backup_*" -mtime "+${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true
find /host-backups -maxdepth 1 -type d -name "backup_*" -mtime "+${BACKUP_RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true

echo "[$(date)] Backup maintenance completed"
SCRIPTEOF

chmod +x /usr/local/bin/backup.sh

# Export variables for cron
export MONGODUMP_URI BACKUP_RETENTION_DAYS

# Set up cron job
HOUR=$(echo "$BACKUP_TIME" | cut -d: -f1)
MINUTE=$(echo "$BACKUP_TIME" | cut -d: -f2)

echo "${MINUTE} ${HOUR} * * * /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/mongodb-backup
chmod 0644 /etc/cron.d/mongodb-backup

# Also write env vars for cron
printenv | grep -E "^(MONGODUMP_URI|BACKUP_RETENTION_DAYS|PATH)" > /etc/environment

echo "[$(date)] Backup cron job scheduled daily at ${BACKUP_TIME}"
echo "[$(date)] Starting cron daemon..."

# Run cron in foreground
exec cron -f
