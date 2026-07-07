#!/bin/bash
# =============================================================================
# generate-keyfile.sh — Generate and Distribute MongoDB Internal Auth Keyfile
# =============================================================================
# Generates a 756-byte base64 keyfile, sets correct permissions, and
# copies it to all 3 hosts. Run once before starting the cluster.
#
# Usage: ./scripts/generate-keyfile.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env for HOST IPs
if [ -f "${REPO_DIR}/.env" ]; then
    source "${REPO_DIR}/.env"
else
    echo "ERROR: .env file not found at ${REPO_DIR}/.env"
    echo "Copy .env.example to .env and configure host IPs first."
    exit 1
fi

KEYFILE="${REPO_DIR}/keyfile"
REMOTE_PATH="/opt/mongodb-cluster-shard-docker/keyfile"

echo "=== Generating MongoDB Internal Auth Keyfile ==="

# Generate keyfile
echo "[1/4] Generating keyfile..."
openssl rand -base64 756 > "${KEYFILE}"
chmod 400 "${KEYFILE}"
echo "      Created: ${KEYFILE}"

# Copy to Host 2
echo "[2/4] Copying keyfile to Host 2 (${HOST2_IP})..."
scp "${KEYFILE}" "root@${HOST2_IP}:${REMOTE_PATH}" || {
    echo "      WARNING: Failed to copy to ${HOST2_IP}. Please copy manually:"
    echo "      scp ${KEYFILE} root@${HOST2_IP}:${REMOTE_PATH}"
}

# Copy to Host 3
echo "[3/4] Copying keyfile to Host 3 (${HOST3_IP})..."
scp "${KEYFILE}" "root@${HOST3_IP}:${REMOTE_PATH}" || {
    echo "      WARNING: Failed to copy to ${HOST3_IP}. Please copy manually:"
    echo "      scp ${KEYFILE} root@${HOST3_IP}:${REMOTE_PATH}"
}

echo "[4/4] Keyfile distribution complete!"
echo ""
echo "=== Next Steps ==="
echo "1. Ensure the repo is cloned to /opt/mongodb-cluster-shard-docker on all 3 hosts"
echo "2. On each host: cp .env.example .env (with correct HOST IPs)"
echo "3. On each host: docker compose -f docker-compose.host<N>.yml up -d --build"
echo "4. Run: ./scripts/init-cluster.sh"
