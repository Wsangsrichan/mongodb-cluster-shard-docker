#!/bin/bash
# =============================================================================
# init-cluster.sh — Multi-Host MongoDB Sharded Cluster Initialization
# =============================================================================
# Run this AFTER starting docker-compose on all 3 hosts.
# Connects via SSH to each host to run docker exec for rs.initiate(),
# user creation, and shard addition (required due to MongoDB localhost
# exception when authorization is enabled).
#
# Usage: ./scripts/init-cluster.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env
if [ -f "${REPO_DIR}/.env" ]; then
    source "${REPO_DIR}/.env"
else
    echo "ERROR: .env file not found at ${REPO_DIR}/.env"
    exit 1
fi

HOST1="${HOST1_IP:-10.0.0.1}"
HOST2="${HOST2_IP:-10.0.0.2}"
HOST3="${HOST3_IP:-10.0.0.3}"

MONGO_USER="${MONGO_INITDB_ROOT_USERNAME:-admin}"
MONGO_PASS="${MONGO_INITDB_ROOT_PASSWORD:-changeme}"
MONITOR_USER="${MONGO_MONITOR_USER:-monitor}"
MONITOR_PASS="${MONGO_MONITOR_PASSWORD:-changeme}"

# Docker exec wrapper functions
# Host 1
exec_h1() {
    local container="$1"; shift
    ssh root@${HOST1} "docker exec ${container} mongosh --quiet $*"
}
# Host 2
exec_h2() {
    local container="$1"; shift
    ssh root@${HOST2} "docker exec ${container} mongosh --quiet $*"
}
# Host 3
exec_h3() {
    local container="$1"; shift
    ssh root@${HOST3} "docker exec ${container} mongosh --quiet $*"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ----------------------------------------------------------------------
# Step 1: Wait for all 9 mongod nodes to be ready
# ----------------------------------------------------------------------
log "========================================="
log "Step 1: Waiting for all mongod nodes..."
log "========================================="

wait_mongo() {
    local host="$1"
    local container="$2"
    local max_attempts=60
    local attempt=1

    log "  Waiting for ${container} on ${host}..."
    while [ $attempt -le $max_attempts ]; do
        if ssh root@${host} "docker exec ${container} mongosh --quiet --eval 'db.runCommand({ping:1})'" &>/dev/null; then
            log "  ${container} is ready"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    log "  ERROR: ${container} on ${host} did not become ready"
    return 1
}

# Host 1 nodes
wait_mongo "${HOST1}" "configdb-replica0"
wait_mongo "${HOST1}" "shard0-replica0"
wait_mongo "${HOST1}" "shard1-replica1"

# Host 2 nodes
wait_mongo "${HOST2}" "configdb-replica1"
wait_mongo "${HOST2}" "shard0-replica1"
wait_mongo "${HOST2}" "shard1-replica0"

# Host 3 nodes
wait_mongo "${HOST3}" "configdb-replica2"
wait_mongo "${HOST3}" "shard0-replica2"
wait_mongo "${HOST3}" "shard1-replica2"

log "All 9 mongod nodes are ready!"

# ----------------------------------------------------------------------
# Step 2: Initiate replica sets
# ----------------------------------------------------------------------
log "========================================="
log "Step 2: Initiating replica sets..."
log "========================================="

initiate_rep_set() {
    local host="$1"
    local container="$2"
    local rep_set="$3"
    shift 3
    # Remaining args are "host:port" pairs

    log "  Initiating ${rep_set} via ${container} on ${host}..."

    # Build members JSON array
    local members=""
    local i=0
    for member in "$@"; do
        members+="{ _id: ${i}, host: \"${member}\" },"
        i=$((i + 1))
    done

    local configsvr_flag=""
    if [ "$rep_set" = "configdb" ]; then
        configsvr_flag="configsvr: true,"
    fi

    ssh root@${host} "docker exec ${container} mongosh --quiet --eval \"
        var result;
        try {
            var cfg = rs.conf();
            result = 'ALREADY_INITED';
        } catch(e) {
            result = 'NOT_INITED';
        }
        if (result === 'NOT_INITED') {
            rs.initiate({
                _id: '${rep_set}',
                ${configsvr_flag}
                members: [${members}]
            });
            while (rs.status().myState !== 1) {
                sleep(1000);
            }
            print('INITIATED');
        } else {
            print('SKIPPED');
        }
    \""
}

log "--- Config Server Replica Set ---"
initiate_rep_set "${HOST1}" "configdb-replica0" "configdb" \
    "${HOST1}:27017" "${HOST2}:27017" "${HOST3}:27017"

log "--- Shard 0 Replica Set ---"
initiate_rep_set "${HOST1}" "shard0-replica0" "shard0" \
    "${HOST1}:27017" "${HOST2}:27017" "${HOST3}:27017"

log "--- Shard 1 Replica Set ---"
initiate_rep_set "${HOST2}" "shard1-replica0" "shard1" \
    "${HOST2}:27017" "${HOST1}:27017" "${HOST3}:27017"

log "All replica sets initiated."

# ----------------------------------------------------------------------
# Step 3: Wait for primary elections
# ----------------------------------------------------------------------
log "========================================="
log "Step 3: Waiting for primary elections (15s)..."
log "========================================="
sleep 15

# ----------------------------------------------------------------------
# Step 4: Create admin users on each replica set primary
# ----------------------------------------------------------------------
log "========================================="
log "Step 4: Creating admin users on each replica set..."
log "========================================="

create_admin_user() {
    local host="$1"
    local container="$2"
    local rep_set_name="$3"

    log "  Creating admin user on ${rep_set_name} via ${container} on ${host}..."
    ssh root@${host} "docker exec ${container} mongosh --quiet --eval \"
        var users = db.getSiblingDB('admin').getUsers();
        var exists = users.some(function(u) { return u.user === '${MONGO_USER}'; });
        if (!exists) {
            db.getSiblingDB('admin').createUser({
                user: '${MONGO_USER}',
                pwd: '${MONGO_PASS}',
                roles: [
                    { role: 'root', db: 'admin' },
                    { role: 'clusterAdmin', db: 'admin' }
                ]
            });
            print('CREATED');
        } else {
            print('EXISTS');
        }
    \""
}

create_admin_user "${HOST1}" "configdb-replica0" "configdb"
create_admin_user "${HOST1}" "shard0-replica0" "shard0"
create_admin_user "${HOST2}" "shard1-replica0" "shard1"

# ----------------------------------------------------------------------
# Step 5: Create monitor user
# ----------------------------------------------------------------------
log "========================================="
log "Step 5: Creating monitor user on configdb..."
log "========================================="

ssh root@${HOST1} "docker exec configdb-replica0 mongosh --quiet \
    -u ${MONGO_USER} -p ${MONGO_PASS} --authenticationDatabase admin --eval \"
    var users = db.getSiblingDB('admin').getUsers();
    var exists = users.some(function(u) { return u.user === '${MONITOR_USER}'; });
    if (!exists) {
        db.getSiblingDB('admin').createUser({
            user: '${MONITOR_USER}',
            pwd: '${MONITOR_PASS}',
            roles: [
                { role: 'clusterMonitor', db: 'admin' },
                { role: 'read', db: 'local' }
            ]
        });
        print('MONITOR_CREATED');
    } else {
        print('MONITOR_EXISTS');
    }
\""

log "Monitor user created."

# ----------------------------------------------------------------------
# Step 6: Wait for mongos routers
# ----------------------------------------------------------------------
log "========================================="
log "Step 6: Waiting for mongos routers..."
log "========================================="

wait_mongo "${HOST1}" "mongos-router0"
wait_mongo "${HOST2}" "mongos-router1"

# ----------------------------------------------------------------------
# Step 7: Add shards to the cluster
# ----------------------------------------------------------------------
log "========================================="
log "Step 7: Adding shards to cluster..."
log "========================================="

add_shard() {
    local host="$1"
    local container="$2"
    local shard_name="$3"
    local shard_rs="$4"

    log "  Adding shard '${shard_name}'..."
    ssh root@${host} "docker exec ${container} mongosh --quiet \
        -u ${MONGO_USER} -p ${MONGO_PASS} --authenticationDatabase admin --eval \"
        var shards = db.adminCommand({listShards: 1}).shards || [];
        var found = shards.some(function(s) { return s._id === '${shard_name}'; });
        if (!found) {
            sh.addShard('${shard_rs}');
            print('ADDED');
        } else {
            print('EXISTS');
        }
    \""
}

add_shard "${HOST1}" "mongos-router0" "shard0" \
    "shard0/${HOST1}:27017,${HOST2}:27017,${HOST3}:27017"

add_shard "${HOST1}" "mongos-router0" "shard1" \
    "shard1/${HOST2}:27017,${HOST1}:27017,${HOST3}:27017"

# ----------------------------------------------------------------------
# Step 8: Verify cluster
# ----------------------------------------------------------------------
log "========================================="
log "Step 8: Verifying cluster status..."
log "========================================="

ssh root@${HOST1} "docker exec mongos-router0 mongosh --quiet \
    -u ${MONGO_USER} -p ${MONGO_PASS} --authenticationDatabase admin --eval 'sh.status()'"

log "========================================="
log "Cluster initialization completed!"
log ""
log "Access points:"
log "  Mongos (direct):  ${HOST1}:27017  or  ${HOST2}:27018"
log "  Mongos (HAProxy):  ${HOST3}:27017"
log "  Prometheus:        http://${HOST1}:9090"
log "  Grafana:           http://${HOST3}:3000  (admin / admin)"
log "========================================="
