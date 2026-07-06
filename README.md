# MongoDB Sharded Cluster with Docker

A production-like MongoDB sharded cluster running entirely in Docker Compose, complete with monitoring (Prometheus + Grafana) and automated backups.

## Architecture

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
    │ 11x MongoDB Exporters (percona) :9216   │
    │  (one per mongod/mongos instance)       │
    └─────────────────────────────────────────┘
```

**Components:**
- **3 Config Servers** (`configdb-replica0/1/2`) — store cluster metadata
- **2 Shards** with 3 replicas each (`shard0-replica0/1/2`, `shard1-replica0/1/2`) — store actual data
- **2 Mongos Routers** (`mongos-router0:27017`, `mongos-router1:27018`) — query routing
- **Coordinator** — one-time init: replica sets, shard setup, user creation
- **Prometheus** (`:9090`) — metrics collection from MongoDB exporters
- **Grafana** (`:3000`) — dashboards and visualization
- **Backup Service** — automated daily mongodump with retention

## Prerequisites

- **Docker** 20.10+ and **Docker Compose** v2+
- At least **8 GB RAM** available for Docker (the full cluster uses significant resources)
- macOS / Linux (Windows with WSL2 should also work)

## Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Wsangsrichan/mongodb-cluster-shard-docker.git
   cd mongodb-cluster-shard-docker
   ```

2. **Create your environment file:**
   ```bash
   cp .env.example .env
   ```

   Edit `.env` to set secure passwords:
   ```
   MONGO_INITDB_ROOT_USERNAME=admin
   MONGO_INITDB_ROOT_PASSWORD=your_secure_password
   MONGO_MONITOR_USER=monitor
   MONGO_MONITOR_PASSWORD=your_monitor_password
   ```

3. **Start the cluster:**
   ```bash
   docker compose up -d
   ```

   The initial startup takes a few minutes as the coordinator waits for all nodes to be healthy, initiates replica sets, and configures sharding.

4. **Check status:**
   ```bash
   docker compose ps
   docker compose logs coordinator
   ```

## Access Points

| Service    | Address          | Description                    |
|------------|------------------|--------------------------------|
| **Mongos** | `localhost:27017` | Primary query router           |
| **Mongos** | `localhost:27018` | Secondary query router         |
| **Grafana**| `localhost:3000`  | Monitoring dashboards          |
| **Prometheus**| `localhost:9090`| Metrics and alerting           |

## Connecting with mongosh

```bash
# Connect to the cluster via mongos
mongosh "mongodb://admin:your_secure_password@localhost:27017/admin?authSource=admin"

# Check cluster status
sh.status()

# List databases
show dbs
```

If you don't have `mongosh` installed, you can use it from within the Docker network:
```bash
docker compose exec mongos-router0 mongosh --eval "sh.status()"
```

## Monitoring

### Grafana Dashboard

1. Open Grafana at http://localhost:3000
   - Default credentials: `admin` / `admin`
2. Add a Prometheus data source:
   - Go to **Connections → Data Sources → Add data source → Prometheus**
   - Set URL to `http://prometheus:9090`
   - Name it `Prometheus` (required for the dashboard to work)
   - Click **Save & Test**
3. Import the dashboard:
   - Go to **Dashboards → New → Import**
   - Upload `grafana/dashboard-14997.json` or paste its contents
   - Select the `Prometheus` data source
   - Click **Import**

The dashboard (ID 14997) is a fork of the popular "MongoDB Prometheus Exporter Dashboard" and uses the Grafana v2 API format (compatible with Grafana 11+).

### Prometheus

Open http://localhost:9090 to explore metrics directly, run queries, and check targets status.

## Backup

Backups run automatically as a daily cron job (default: 1:00 AM UTC).

**Configuration (in `.env` or docker-compose.yml):**
- `BACKUP_TIME` — cron schedule (default: `01:00`)
- `BACKUP_RETENTION_DAYS` — days to keep backups (default: `7`)

**Backup locations:**
- Container: `/tmp/backups/backup_YYYYMMDD_HHMMSS/`
- Host: `./backups/backup_YYYYMMDD_HHMMSS/` (mounted volume)

## Cleanup

To stop and remove everything (including data volumes):

```bash
docker compose down -v
```

To stop without removing data:
```bash
docker compose down
```

## File Structure

```
├── docker-compose.yml       # Full cluster definition
├── .env.example             # Template for environment variables
├── .gitignore               # Ignore .env and data dirs
├── prometheus.yml           # Prometheus scrape config
├── README.md                # This file
├── mongod/
│   ├── Dockerfile           # Builds MongoDB 7.0 shard/config server image
│   └── mongod.conf          # Mongod configuration (auth, replication)
├── mongos/
│   ├── Dockerfile           # Builds MongoDB 7.0 mongos router image
│   └── mongos.conf          # Mongos configuration (net only)
├── coordinator/
│   ├── Dockerfile           # Builds init container image
│   └── init.sh              # Cluster initialization script
├── backup/
│   └── entrypoint.sh        # Automated backup cron setup
└── grafana/
    └── dashboard-14997.json  # MongoDB monitoring dashboard (Grafana v2 API)
```

## Resource Usage

This cluster runs **15 MongoDB containers** (9 mongod + 2 mongos + 11 exporters + coordinator + backup + monitoring), which requires significant resources:

- **RAM:** ~4-6 GB minimum, 8 GB recommended
- **Disk:** ~2-5 GB for data volumes (grows with usage)
- **CPU:** Multi-core recommended

To reduce resource usage, you can comment out unused exporters or shards in `docker-compose.yml`.

## Notes

- **No TLS:** This configuration is intended for local development. TLS is disabled for simplicity.
- **KeyFile:** The cluster uses a keyfile for internal authentication (`/etc/mongod-keyfile`). In production, generate a secure keyfile and mount it.
- **Networking:** All services communicate over the Docker `internalnetwork`. Host ports are exposed only for mongos, Grafana, and Prometheus.
- **Idempotency:** The coordinator script can be re-run safely; it skips steps that are already complete.

## License

MIT
