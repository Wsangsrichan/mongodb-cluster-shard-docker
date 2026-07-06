#!/bin/bash
# ----------------------------------------------------------------------
# MongoDB Sharded Cluster Initialization Script
#
# Runs once to:
#   1. Wait for all mongod replicas to be ready
#   2. Initiate replica sets for configdb, shard0, and shard1
#   3. Add shards to the cluster via mongos
#   4. Create admin and monitor users
#
# Idempotent: skips steps that are already done.
# ----------------------------------------------------------------------

set -e

MONGO_INITDB_ROOT_USERNAME="${MONGO_INITDB_ROOT_USERNAME:-admin}"
MONGO_INITDB_ROOT_PASSWORD="${MONGO_INITDB_ROOT_PASSWORD:-changeme}"
MONGO_MONITOR_USER="${MONGO_MONITOR_USER:-monitor}"
MONGO_MONITOR_PASSWORD="${MONGO_MONITOR_PASSWORD:-changeme}"

# Mongo shell with common options (no TLS for local dev)
MONGO="mongosh --quiet --tlsAllowInvalidCertificates --tlsAllowInvalidHostnames"

# ----------------------------------------------------------------------
# Helper: log messages
# ----------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ----------------------------------------------------------------------
# Helper: wait until mongod is reachable
# ----------------------------------------------------------------------
wait_for_mongo() {
    local host="$1"
    local port="${2:-27017}"
    local max_attempts="${3:-60}"
    local attempt=1

    log "Waiting for $host:$port ..."
    while [ $attempt -le $max_attempts ]; do
        if $MONGO "mongodb://$host:$port" --eval "db.runCommand('ping')" > /dev/null 2>&1; then
            log "$host:$port is ready"
            return 0
        fi
        log "Attempt $attempt/$max_attempts: $host:$port not ready yet..."
        sleep 5
        attempt=$((attempt + 1))
    done
    log "ERROR: $host:$port did not become ready in time"
    return 1
}

# ----------------------------------------------------------------------
# Helper: initiate replica set if not already initialized
# ----------------------------------------------------------------------
init_repset() {
    local rep_set="$1"
    shift
    local members=("$@")
    local primary="${members[0]}"
    local member_objects=""

    for member in "${members[@]}"; do
        local host="${member%%:*}"
        local port="${member##*:}"
        member_objects+="{\"_id\":${#member_objects#*{}}, host:\"$host:$port\"},"
    done

    log "Initiating replica set '$rep_set'..."

    # Check if already initialized
    local state
    state=$($MONGO "mongodb://$primary/admin" --eval "
        try {
            var cfg = rs.conf();
            print(cfg._id);
        } catch(e) {
            print('NOT_INITED');
        }
    " 2>/dev/null)

    if echo "$state" | grep -q "NOT_INITED"; then
        log "Replica set '$rep_set' not yet initialized, doing rs.initiate() now..."
        $MONGO "mongodb://$primary/admin" --eval "
            rs.initiate({
                _id: '$rep_set',
                members: [$member_objects]
            });
            while (rs.status().myState !== 1) {
                sleep(1000);
            }
        " > /dev/null 2>&1
        log "Replica set '$rep_set' initiated successfully"
    else
        log "Replica set '$rep_set' already initialized, skipping"
    fi
}

# ----------------------------------------------------------------------
# Helper: add shard to cluster
# ----------------------------------------------------------------------
add_shard() {
    local shard_name="$1"
    local shard_rs="$2"  # e.g. "shard0/shard0-replica0:27017,shard0-replica1:27017,shard0-replica2:27017"

    log "Adding shard '$shard_name'..."

    local result
    result=$($MONGO "mongodb://mongos-router0:27017/admin" --eval "
        var shards = db.adminCommand({listShards: 1}).shards || [];
        var found = shards.some(function(s) { return s._id === '$shard_name'; });
        if (!found) {
            sh.addShard('$shard_rs');
            print('ADDED');
        } else {
            print('EXISTS');
        }
    " 2>/dev/null)

    if echo "$result" | grep -q "ADDED"; then
        log "Shard '$shard_name' added successfully"
    else
        log "Shard '$shard_name' already exists, skipping"
    fi
}

# ----------------------------------------------------------------------
# Helper: create users if they don't already exist
# ----------------------------------------------------------------------
create_users() {
    log "Creating users via mongos..."

    $MONGO "mongodb://mongos-router0:27017/admin" --eval "
        // Create root user
        var rootExists = db.getUsers().some(function(u) { return u.user === '$MONGO_INITDB_ROOT_USERNAME'; });
        if (!rootExists) {
            db.createUser({
                user: '$MONGO_INITDB_ROOT_USERNAME',
                pwd: '$MONGO_INITDB_ROOT_PASSWORD',
                roles: [
                    { role: 'root', db: 'admin' },
                    { role: 'clusterAdmin', db: 'admin' }
                ]
            });
            print('Root user created');
        } else {
            print('Root user already exists');
        }

        // Create monitor user
        var monitorExists = db.getUsers().some(function(u) { return u.user === '$MONGO_MONITOR_USER'; });
        if (!monitorExists) {
            db.createUser({
                user: '$MONGO_MONITOR_USER',
                pwd: '$MONGO_MONITOR_PASSWORD',
                roles: [
                    { role: 'clusterMonitor', db: 'admin' },
                    { role: 'read', db: 'local' }
                ]
            });
            print('Monitor user created');
        } else {
            print('Monitor user already exists');
        }
    " > /dev/null 2>&1

    log "User creation completed"
}

# ======================================================================
# MAIN
# ======================================================================

log "========================================="
log "MongoDB Sharded Cluster Initialization"
log "========================================="

# ----------------------------------------------------------------------
# Step 1: Wait for all mongod nodes
# ----------------------------------------------------------------------
log "Step 1: Waiting for configdb nodes..."
wait_for_mongo configdb-replica0
wait_for_mongo configdb-replica1
wait_for_mongo configdb-replica2

log "Step 1: Waiting for shard0 nodes..."
wait_for_mongo shard0-replica0
wait_for_mongo shard0-replica1
wait_for_mongo shard0-replica2

log "Step 1: Waiting for shard1 nodes..."
wait_for_mongo shard1-replica0
wait_for_mongo shard1-replica1
wait_for_mongo shard1-replica2

# ----------------------------------------------------------------------
# Step 2: Initiate replica sets
# ----------------------------------------------------------------------
log "Step 2: Initiating replica sets..."

init_repset "configdb" \
    "configdb-replica0:27017" \
    "configdb-replica1:27017" \
    "configdb-replica2:27017"

init_repset "shard0" \
    "shard0-replica0:27017" \
    "shard0-replica1:27017" \
    "shard0-replica2:27017"

init_repset "shard1" \
    "shard1-replica0:27017" \
    "shard1-replica1:27017" \
    "shard1-replica2:27017"

# ----------------------------------------------------------------------
# Step 3: Wait for mongos routers
# ----------------------------------------------------------------------
log "Step 3: Waiting for mongos routers..."
wait_for_mongo mongos-router0
wait_for_mongo mongos-router1

# ----------------------------------------------------------------------
# Step 4: Add shards
# ----------------------------------------------------------------------
log "Step 4: Adding shards to cluster..."

add_shard "shard0" "shard0/shard0-replica0:27017,shard0-replica1:27017,shard0-replica2:27017"
add_shard "shard1" "shard1/shard1-replica0:27017,shard1-replica1:27017,shard1-replica2:27017"

# ----------------------------------------------------------------------
# Step 5: Create users
# ----------------------------------------------------------------------
log "Step 5: Creating admin and monitor users..."
create_users

# ----------------------------------------------------------------------
# Done
# ----------------------------------------------------------------------
log "========================================="
log "Cluster initialization completed!"
log "========================================="

# Mark as done to prevent re-runs
touch /init-state/.init-done

exit 0
