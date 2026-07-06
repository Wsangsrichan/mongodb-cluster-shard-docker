#!/bin/bash
# ----------------------------------------------------------------------
# MongoDB Entrypoint Wrapper
#
# Waits for the internal auth keyfile from the coordinator, copies it
# to /etc/mongod-keyfile, then starts mongod with the config file and
# any extra arguments passed from docker-compose command.
# ----------------------------------------------------------------------

set -e

echo "[$(date)] Waiting for keyfile from coordinator..."
while [ ! -f /init-state/keyfile ]; do
  sleep 2
done

cp /init-state/keyfile /etc/mongod-keyfile
chmod 400 /etc/mongod-keyfile
echo "[$(date)] Keyfile received, starting mongod..."

exec mongod -f /etc/mongod.conf "$@"
