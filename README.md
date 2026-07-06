# 🍃 MongoDB Sharded Cluster with Docker Compose

A production-like MongoDB sharded cluster running entirely in Docker Compose, complete with monitoring (Prometheus + Grafana) and automated daily backups using `mongodump`.

## 🏗 Architecture

```
                         ┌──────────────────────────────────┐
                         │         Client / mongosh          │
                         └──────────────┬───────────────────┘
                                        │
                          ┌─────────────┴─────────────┐
                          │    mongos-router0 (:27017) │
                          │    mongos-router1 (:27018) │
                          └─────────────┬─────────────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              │                         │                         │
    ┌─────────┴─────────┐     ┌────────┴────────┐     ┌──────────┴──────────┐
    │   Config Replica  │     │   Shard 0 RS    │     │    Shard 1 RS       │
    │     (configdb)     │     │                 │     │                     │
    │  ┌──────────────┐ │     │ ┌─────────────┐ │     │ ┌─────────────────┐ │
    │  │ replica0     │ │     │ │ replica0     │ │     │ │ replica0         │ │
    │  │ replica1     │ │     │ │ replica1     │ │     │ │ replica1         │ │
    │  │ replica2     │ │     │ │ replica2     │ │     │ │ replica2         │ │
    │  └──────────────┘ │     │ └─────────────┘ │     │ └─────────────────┘ │
    └───────────────────┘     └─────────────────┘     └─────────────────────┘

  ┌──────────────┐  ┌────────────────┐  ┌─────────────────┐  ┌───────────────┐
  │  Prometheus  │  │    Grafana     │  │  Node Exporter  │  │   MongoDB     │
  │   (:9090)    │  │    (:3000)     │  │    (:9100)      │  │   Backup Svc  │
  └──────┬───────┘  └────────────────┘  └─────────────────┘  └───────────────┘
         │
    ┌────┴────────────────────────────────────┐
    │ 11× MongoDB Exporters (percona) :9216   │
    │  (one per mongod/mongos instance)       │
    └─────────────────────────────────────────┘
```

**Components:**

- **3 Config Servers** (`configdb-replica0/1/2`) — store cluster metadata
- **2 Shards** with 3 replicas each (`shard0-replica0/1/2`, `shard1-replica0/1/2`) — store actual data
- **2 Mongos Routers** (`mongos-router0:27017`, `mongos-router1:27018`) — query routing
- **Coordinator** — one-time init: generates keyfile, waits for nodes, creates users
- **Prometheus** (`:9090`) — metrics collection from MongoDB exporters
- **Grafana** (`:3000`) — dashboards and visualization
- **Backup Service** — automated daily `mongodump` with configurable retention

## 📋 Prerequisites

- **Docker** 20.10+ and **Docker Compose** v2+
- At least **4–5 GB RAM** available for Docker
- **Linux** (tested on Ubuntu 24.04)
- ~2–5 GB free disk space for data volumes

## 🚀 Quick Start

Follow these steps carefully to get the cluster running. **Steps 4–8 must be run manually** due to MongoDB's localhost exception — the coordinator cannot run `rs.initiate()` from a separate container when `authorization: enabled` is set.

### 1. Clone and configure

```bash
git clone https://github.com/Wsangsrichan/mongodb-cluster-shard-docker.git
cd mongodb-cluster-shard-docker
cp .env.example .env
```

Edit `.env` to set strong passwords:

```env
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=your_strong_password_here
MONGO_MONITOR_USER=monitor
MONGO_MONITOR_PASSWORD=your_monitor_password_here
```

### 2. Start all containers

```bash
docker compose up -d --build
```

This starts all 9 `mongod` nodes, 2 `mongos` routers, the coordinator (which generates the keyfile and waits for nodes), plus Prometheus and Grafana.

### 3. Wait for all nodes to be ready

```bash
sleep 30
```

You can verify nodes are listening with:

```bash
docker compose ps
```

### 4. Initialize replica sets

> ⚠️ **Important:** These commands **must** be run via `docker exec` (not from the coordinator container) because MongoDB's localhost exception only allows `rs.initiate()` from localhost when `authorization: enabled` is set.

**Config server replica set:**

```bash
docker exec mongodb-cluster-shard-docker-configdb-replica0-1 mongosh --quiet --eval '
rs.initiate({
  _id: "configdb",
  configsvr: true,
  members: [
    { _id: 0, host: "configdb-replica0:27017" },
    { _id: 1, host: "configdb-replica1:27017" },
    { _id: 2, host: "configdb-replica2:27017" }
  ]
})'
```

**Shard 0 replica set:**

```bash
docker exec mongodb-cluster-shard-docker-shard0-replica0-1 mongosh --quiet --eval '
rs.initiate({
  _id: "shard0",
  members: [
    { _id: 0, host: "shard0-replica0:27017" },
    { _id: 1, host: "shard0-replica1:27017" },
    { _id: 2, host: "shard0-replica2:27017" }
  ]
})'
```

**Shard 1 replica set:**

```bash
docker exec mongodb-cluster-shard-docker-shard1-replica0-1 mongosh --quiet --eval '
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1-replica0:27017" },
    { _id: 1, host: "shard1-replica1:27017" },
    { _id: 2, host: "shard1-replica2:27017" }
  ]
})'
```

### 5. Wait for primary elections

```bash
sleep 15
```

Each replica set needs time to hold an election and select a primary. You can check with:

```bash
docker exec mongodb-cluster-shard-docker-configdb-replica0-1 mongosh --quiet --eval "rs.status().members.map(m => ({name: m.name, stateStr: m.stateStr}))"
```

### 6. Create admin users on each replica set

Since `authorization: enabled` is active, you must create users **before** the mongos routers can connect with authentication.

```bash
# Config server
docker exec mongodb-cluster-shard-docker-configdb-replica0-1 mongosh --quiet --eval "
db.getSiblingDB('admin').createUser({
  user: 'admin',
  pwd: 'YOUR_PASSWORD',
  roles: [
    { role: 'root', db: 'admin' },
    { role: 'clusterAdmin', db: 'admin' }
  ]
})"

# Shard 0
docker exec mongodb-cluster-shard-docker-shard0-replica0-1 mongosh --quiet --eval "
db.getSiblingDB('admin').createUser({
  user: 'admin',
  pwd: 'YOUR_PASSWORD',
  roles: [{ role: 'root', db: 'admin' }]
})"

# Shard 1
docker exec mongodb-cluster-shard-docker-shard1-replica0-1 mongosh --quiet --eval "
db.getSiblingDB('admin').createUser({
  user: 'admin',
  pwd: 'YOUR_PASSWORD',
  roles: [{ role: 'root', db: 'admin' }]
})"
```

> Replace `YOUR_PASSWORD` with the value you set for `MONGO_INITDB_ROOT_PASSWORD` in `.env`.

### 7. Create monitor user (for Prometheus exporters)

```bash
docker exec mongodb-cluster-shard-docker-configdb-replica0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "
db.getSiblingDB('admin').createUser({
  user: 'monitor',
  pwd: 'YOUR_MONITOR_PASSWORD',
  roles: [
    { role: 'clusterMonitor', db: 'admin' },
    { role: 'read', db: 'local' }
  ]
})"
```

> Replace `YOUR_MONITOR_PASSWORD` with the value from `MONGO_MONITOR_PASSWORD` in `.env`.

### 8. Add shards to the cluster

Now that users exist, the mongos routers can authenticate:

```bash
docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "
sh.addShard('shard0/shard0-replica0:27017,shard0-replica1:27017,shard0-replica2:27017')"

docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "
sh.addShard('shard1/shard1-replica0:27017,shard1-replica1:27017,shard1-replica2:27017')"
```

### 9. Verify the cluster

```bash
docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "sh.status()"
```

You should see both shards listed with `state: 1` (active).

## 🔌 Access Points

| Service | Address | Description |
|---|---|---|
| **Mongos Router 0** | `localhost:27017` | Primary query router |
| **Mongos Router 1** | `localhost:27018` | Secondary query router |
| **Grafana** | `http://localhost:3000` | Monitoring dashboards |
| **Prometheus** | `http://localhost:9090` | Metrics and alerting |

## 💻 Connecting with mongosh

From your host machine (requires `mongosh` installed):

```bash
mongosh "mongodb://admin:YOUR_PASSWORD@localhost:27017/admin"
```

Or directly inside a container:

```bash
docker exec -it mongodb-cluster-shard-docker-mongos-router0-1 mongosh \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin
```

If you don't have `mongosh` installed locally, use `docker exec` as shown above.

## 🧪 Test Sharding

To verify sharding is working correctly, enable sharding on a test database, create a sharded collection, and insert some data:

```bash
docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "
sh.enableSharding('testdb');
sh.shardCollection('testdb.testcoll', { _id: 'hashed' });
for (let i = 0; i < 1000; i++) {
  db.getSiblingDB('testdb').testcoll.insertOne({ _id: i, value: 'data-' + i });
}
db.getSiblingDB('testdb').testcoll.getShardDistribution()
"
```

The output of `getShardDistribution()` should show data distributed across both shards.

## 📊 Monitoring

### Grafana Dashboard

1. Open Grafana at http://localhost:3000
   - Default credentials: `admin` / `admin`
2. Add a Prometheus data source:
   - Go to **Connections → Data Sources → Add data source → Prometheus**
   - Set URL to `http://prometheus:9090`
   - Name it `Prometheus` (required for the dashboard JSON to work)
   - Click **Save & Test**
3. Import the dashboard:
   - Go to **Dashboards → New → Import**
   - Upload `grafana/dashboard-14997.json` or paste its contents
   - Select the `Prometheus` data source
   - Click **Import**

The dashboard (ID 14997) is a fork of the popular "MongoDB Prometheus Exporter Dashboard" compatible with Grafana 11+.

### Prometheus

Open http://localhost:9090 to explore metrics directly, run queries, and check targets status. All 11 MongoDB exporters should appear as "UP" under **Status → Targets**.

## 💾 Backup

Backups run automatically as a daily job (default: 1:00 AM UTC).

**Configuration (via `.env`):**

- `BACKUP_TIME` — cron-style time (default: `01:00`)
- `BACKUP_RETENTION_DAYS` — days to keep backups (default: `7`)

**Backup locations:**

- Container: `/tmp/backups/backup_YYYYMMDD_HHMMSS/`
- Host: `./backups/backup_YYYYMMDD_HHMMSS/` (mounted volume)

To run a manual backup immediately:

```bash
docker exec mongodb-cluster-shard-docker-backup-1 mongodump \
  --uri="mongodb://admin:YOUR_PASSWORD@mongos-router0:27017/admin?authSource=admin" \
  --out="/tmp/backups/manual_$(date +%Y%m%d_%H%M%S)" --gzip
```

## 🧹 Cleanup

Stop and remove everything **including data volumes**:

```bash
docker compose down -v
```

Stop without removing data (safe to restart later):

```bash
docker compose down
```

## 📁 File Structure

```
├── docker-compose.yml         # Full cluster definition
├── .env.example               # Template for environment variables
├── .gitignore                 # Ignore .env and data dirs
├── prometheus.yml             # Prometheus scrape config
├── README.md                  # This file
├── mongod/
│   ├── Dockerfile             # Builds MongoDB mongod image (shard/config server)
│   ├── mongod.conf            # Mongod configuration (auth, replication)
│   └── entrypoint.sh          # Entrypoint script for mongod containers
├── mongos/
│   ├── Dockerfile             # Builds MongoDB mongos router image
│   └── mongos.conf            # Mongos configuration (net only)
├── coordinator/
│   ├── Dockerfile             # Builds init container image
│   └── init.sh                # Generates keyfile, waits for nodes, creates users
├── backup/
│   └── entrypoint.sh          # Automated daily backup with retention
└── grafana/
    └── dashboard-14997.json   # MongoDB monitoring dashboard (Grafana v2 API)
```

## 📈 Resource Usage

This cluster runs **15 MongoDB-related containers** (9 mongod + 2 mongos + 11 exporters + coordinator + backup + monitoring), which requires significant resources:

- **RAM:** ~4–5 GB minimum, 8 GB recommended
- **Disk:** ~2–5 GB for data volumes (grows with usage)
- **CPU:** Multi-core recommended

To reduce resource usage, you can comment out unused exporters or shards in `docker-compose.yml`.

## ⚠️ Notes & Known Issues

- **Manual `rs.initiate()` required:** The coordinator script generates the keyfile and waits for nodes, but it **cannot** execute `rs.initiate()` from a separate container when `authorization: enabled` is set. This is due to MongoDB's [localhost exception](https://www.mongodb.com/docs/manual/core/localhost-exception/) — only `docker exec` (which runs as localhost) can perform the initial replica set initiation. Steps 4–8 of the Quick Start above must be done manually.

- **No TLS:** This configuration is intended for local development only. TLS is disabled for simplicity.

- **Keyfile:** The cluster uses an internally generated keyfile (`/init-state/keyfile`) for intra-cluster authentication. The coordinator generates this on first startup.

- **Networking:** All services communicate over the Docker `internalnetwork`. Host ports are exposed only for mongos routers, Grafana, and Prometheus.

- **Coordinator idempotency:** The coordinator script can be re-run safely; it skips steps that are already complete. It marks completion with `/init-state/.init-done`.

## 📄 License

MIT
