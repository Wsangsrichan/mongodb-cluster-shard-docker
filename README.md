# 🍃 MongoDB Sharded Cluster — Multi-Host Docker Deployment

A production-like MongoDB sharded cluster distributed across **3 physical/virtual hosts** using Docker Compose, complete with monitoring (Prometheus + Grafana), HAProxy load balancing, and automated daily backups.

## 🏗 Architecture

```
                        ┌──────────────────────────────┐
                        │       Client / mongosh        │
                        └──────────────┬───────────────┘
                                       │
                         ┌─────────────┴─────────────┐
                         │  HAProxy (Host 3 :27017)  │
                         └─────────────┬─────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
          ┌─────────┴─────────┐ ┌──────┴──────┐ ┌────────┴────────┐
          │  Host 1 (10.0.0.1) │ │ Host 2      │ │  Host 3         │
          │                    │ │ (10.0.0.2)  │ │  (10.0.0.3)    │
          │ configdb-replica0  │ │ configdb-r1 │ │ configdb-r2     │
          │ shard0-replica0    │ │ shard0-r1   │ │ shard0-r2       │
          │ shard1-replica1    │ │ shard1-r0   │ │ shard1-r2       │
          │ mongos-router0     │ │ mongos-r1   │ │                 │
          │ Prometheus :9090   │ │              │ │ HAProxy :27017  │
          │ Backup Service     │ │              │ │ Grafana :3000   │
          └────────────────────┘ └──────────────┘ └─────────────────┘
```

**Key design decisions:**
- Each host runs its own `docker-compose.host<N>.yml` on the default bridge network
- All mongod nodes use internal port 27017 (no conflicts — separate hosts)
- Cross-host communication via `${HOST_IP}:PORT`
- Internal auth keyfile synced across hosts via `scripts/generate-keyfile.sh`
- MongoDB exporters: 3 per host, mapped to host ports 9216/9217/9218
- HAProxy on Host 3 load balances between Host 1 and Host 2 mongos routers

## 📋 Prerequisites

- **3 Linux hosts** (Ubuntu 24.04+ recommended) with static IPs
- **Docker** 20.10+ and **Docker Compose** v2+ on each host
- **SSH key access** from your deployment machine to all 3 hosts (root)
- At least **4 GB RAM** per host (8 GB recommended for Host 1)
- **Network:** All 3 hosts must be able to reach each other on ports 27017, 9216-9218, 9090, 9100

## 🚀 Quick Start

### 1. Clone the repo on all 3 hosts

```bash
# On each host:
git clone https://github.com/Wsangsrichan/mongodb-cluster-shard-docker.git /opt/mongodb-cluster-shard-docker
cd /opt/mongodb-cluster-shard-docker
```

### 2. Configure environment

Copy and edit `.env` on each host (or deploy a single `.env` to all 3):

```bash
cp .env.example .env
```

Edit `.env` with your host IPs and strong passwords:

```env
HOST1_IP=10.0.0.1
HOST2_IP=10.0.0.2
HOST3_IP=10.0.0.3
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=your_strong_password
MONGO_MONITOR_USER=monitor
MONGO_MONITOR_PASSWORD=your_monitor_password
```

### 3. Generate and distribute the keyfile

Run from your deployment machine (or Host 1):

```bash
./scripts/generate-keyfile.sh
```

This generates `keyfile` and copies it to Host 2 and Host 3 via SCP.

### 4. Start containers on each host

```bash
# Host 1:
docker compose -f docker-compose.host1.yml up -d --build

# Host 2:
docker compose -f docker-compose.host2.yml up -d --build

# Host 3:
docker compose -f docker-compose.host3.yml up -d --build
```

### 5. Initialize the cluster

Run from your deployment machine (requires SSH access to all 3 hosts):

```bash
./scripts/init-cluster.sh
```

This script will:
1. Wait for all 9 mongod nodes to be ready
2. Initiate replica sets (`configdb`, `shard0`, `shard1`) via SSH + docker exec
3. Create admin users on each replica set primary
4. Create monitor user for Prometheus
5. Add shards to the cluster via mongos
6. Verify cluster status

### 6. Verify the cluster

```bash
# Connect via HAProxy (Host 3):
mongosh "mongodb://admin:YOUR_PASSWORD@10.0.0.3:27017/admin"

# Or directly to a mongos router:
mongosh "mongodb://admin:YOUR_PASSWORD@10.0.0.1:27017/admin"
```

Run `sh.status()` to see both shards active.

## 🔌 Access Points

| Service | Address | Host |
|---------|---------|------|
| **Mongos Router 0** | `10.0.0.1:27017` | Host 1 |
| **Mongos Router 1** | `10.0.0.2:27018` | Host 2 |
| **HAProxy (Load Balanced)** | `10.0.0.3:27017` | Host 3 |
| **Prometheus** | `http://10.0.0.1:9090` | Host 1 |
| **Grafana** | `http://10.0.0.3:3000` | Host 3 |
| **HAProxy Stats** | `http://10.0.0.3:8404` | Host 3 |

## 🧪 Test Sharding

```bash
mongosh "mongodb://admin:YOUR_PASSWORD@10.0.0.3:27017/admin" --eval "
sh.enableSharding('testdb');
sh.shardCollection('testdb.testcoll', { _id: 'hashed' });
for (let i = 0; i < 1000; i++) {
  db.getSiblingDB('testdb').testcoll.insertOne({ _id: i, value: 'data-' + i });
}
db.getSiblingDB('testdb').testcoll.getShardDistribution()
"
```

## 📊 Monitoring

### Prometheus (Host 1)
Open `http://10.0.0.1:9090` to explore metrics. All 9 MongoDB exporters + 3 node exporters should appear UP under **Status → Targets**.

### Grafana (Host 3)
1. Open `http://10.0.0.3:3000` (default: `admin` / `admin`)
2. The Prometheus datasource is pre-configured via provisioning
3. Import dashboard: **Dashboards → New → Import → Upload** `grafana/dashboard-14997.json`

## 💾 Backup

Daily backups run on Host 1 at the configured time (default: 01:00 UTC). Backups are stored in `./backups/` on Host 1.

Manual backup:
```bash
ssh root@10.0.0.1 "docker exec mongodb-backup mongodump \
  --uri='mongodb://admin:YOUR_PASS@localhost:27017/admin?authSource=admin' \
  --out='/tmp/backups/manual_$(date +%Y%m%d_%H%M%S)' --gzip"
```

## 📁 File Structure

```
├── docker-compose.host1.yml    # Host 1 services
├── docker-compose.host2.yml    # Host 2 services
├── docker-compose.host3.yml    # Host 3 services
├── docker-compose.yml           # Original single-host (deprecated)
├── .env.example                 # Template with host IPs
├── .gitignore
├── prometheus.yml               # Prometheus scrape config (multi-host)
├── haproxy/
│   └── haproxy.cfg              # TCP load balancer for mongos
├── scripts/
│   ├── generate-keyfile.sh      # Keyfile generation + distribution
│   └── init-cluster.sh          # Full cluster initialization
├── mongod/
│   ├── Dockerfile
│   ├── mongod.conf
│   └── entrypoint.sh
├── mongos/
│   ├── Dockerfile
│   └── mongos.conf
├── backup/
│   └── entrypoint.sh            # Automated daily backup
├── grafana/
│   ├── dashboard-14997.json     # MongoDB monitoring dashboard
│   └── datasources/
│       └── prometheus.yml       # Auto-provisioned datasource
└── coordinator/                 # Legacy single-host init (deprecated)
```

## 🧹 Cleanup

On each host:
```bash
cd /opt/mongodb-cluster-shard-docker
docker compose -f docker-compose.host1.yml down -v   # Include -v to wipe data
docker compose -f docker-compose.host2.yml down -v
docker compose -f docker-compose.host3.yml down -v
```

## ⚠️ Notes

- **Manual `rs.initiate()` required:** Due to MongoDB's localhost exception with `authorization: enabled`, `rs.initiate()` must run via `docker exec`. The `init-cluster.sh` script automates this via SSH.
- **No TLS:** This configuration is for development/internal networks. TLS is disabled.
- **Keyfile sync:** The keyfile must exist and be identical on all 3 hosts before starting containers.
- **Single-host fallback:** The original `docker-compose.yml` is kept for single-host development.

## 📄 License

MIT
