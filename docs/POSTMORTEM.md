# 🔍 Post-Mortem: `mongodb-cluster-shard-docker`

> การชันสูตรหลังโปรเจกต์ — สิ่งที่ทำถูก สิ่งที่พังยับ และบทเรียนที่เจ็บปวดแต่มีค่า

---

## 📋 ภาพรวมโปรเจกต์ (Project Overview)

| หัวข้อ | รายละเอียด |
|---|---|
| **ชื่อโปรเจกต์** | `mongodb-cluster-shard-docker` |
| **เป้าหมาย** | MongoDB Sharded Cluster บน Docker — **3 hosts** แยกกัน, 9 mongod, 2 shards, monitoring เต็มระบบ |
| **ระยะเวลาพัฒนา** | ~3-4 sessions (ประมาณ 6-8 ชั่วโมงรวม) |
| **จำนวน Commit** | 12 commits |
| **จำนวนไฟล์** | 22 ไฟล์ (สร้างใหม่ 10 + แก้ไข 3 + เพิ่ม multi-host 6 + docs 1) |
| **จำนวน Container** | 26 containers เมื่อ deploy แบบ single-host, ~12-15 ต่อ host ใน multi-host |
| **ภาษา/Stack** | Docker, Docker Compose, MongoDB 8.2, Prometheus, Grafana, HAProxy, Bash |

### ⚙️ สิ่งที่ถูกสร้าง

สิ่งที่เริ่มต้นจาก **3 ไฟล์เปลือย** (prometheus.yml, docker-compose.yml, dashboard-14997.json) กลายเป็นโปรเจกต์ที่ประกอบด้วย:

```
📁 โครงสร้างไฟล์ (22 ไฟล์)
├── 🐳 Docker Compose            docker-compose.yml, host1/2/3.yml (4 ไฟล์)
├── 🗄️ MongoDB images             mongod/{Dockerfile, mongod.conf, entrypoint.sh}
│                                mongos/{Dockerfile, mongos.conf}
├── 🔧 Coordinator               coordinator/{Dockerfile, init.sh}
├── 💾 Backup                     backup/entrypoint.sh
├── 📊 Monitoring                 prometheus.yml, grafana/{dashboard-14997.json, datasources/prometheus.yml}
├── ⚖️ Load Balancer             haproxy/haproxy.cfg
├── 📜 Scripts                    scripts/{generate-keyfile.sh, init-cluster.sh}
├── 📖 เอกสาร                     README.md, docs/OVERVIEW.md, docs/POSTMORTEM.md, .env.example
└── 🔒 Config                     .gitignore
```

---

## ✅ สิ่งที่ทำถูก / สิ่งที่ไปได้ดี (What Went Well)

### 🏗️ การออกแบบสถาปัตยกรรม

| ✅ จุดแข็ง | คำอธิบาย |
|---|---|
| **Topology ถูกต้องตั้งแต่ต้น** | 3 Replica Sets (configdb + shard0 + shard1) × 3 replicas = 9 mongod, 2 mongos — ตรงตาม MongoDB best practices |
| **ใช้ Hashed Sharding** | เลือก `{ _id: "hashed" }` ทำให้ข้อมูลกระจายเท่า ๆ กัน — ผลทดสอบ 1,000 docs ได้ 52/48 split สวยงาม |
| **Keyfile sync ผ่าน shared volume** | Coordinator container สร้าง keyfile → mongod entrypoint รอ + copy จาก `/init-state/` — elegant design, ทำงานได้จริง |
| **Entrypoint pattern** | mongod entrypoint รอ keyfile ก่อน start — แก้ไขปัญหา race condition ได้ดี |

### 🐳 Docker / DevOps

| ✅ จุดแข็ง | คำอธิบาย |
|---|---|
| **Docker build ผ่านฉลุย** | หลังจากแก้ไข path ใน Dockerfile ครั้งเดียว (COPY `init.sh` → `coordinator/init.sh`) — build system ทำงานได้โดยไม่มีปัญหา |
| **Multi-host แยก docker-compose** | ตัดสินใจใช้ compose file แยกต่อ host แทน Docker Swarm — ง่ายกว่า, โปร่งใสกว่า, เหมาะกับ <5 hosts |
| **ใช้ `mongo:latest` ได้ตรง** | ดึง MongoDB 8.2.11 ได้ถูกต้อง ไม่มีปัญหา version mismatch |

### 📊 Monitoring

| ✅ จุดแข็ง | คำอธิบาย |
|---|---|
| **Prometheus scrape ทำงานทันที** | หลังจากแก้ไข auth — ทุก target ขึ้น `UP` ภายในวินาที |
| **Grafana datasource auto-provisioning** | ไฟล์ `grafana/datasources/prometheus.yml` ตั้งค่า datasource อัตโนมัติ — ไม่ต้อง configure เอง |
| **MongoDB Exporters ครบทุกโหนด** | 9 exporters ครอบคลุมทุก mongod + 2 mongos — monitoring coverage 100% |

### 📖 เอกสาร

| ✅ จุดแข็ง | คำอธิบาย |
|---|---|
| **OVERVIEW.md ภาษาไทย** | เขียนด้วยภาษาไทย อธิบาย MongoDB concept ด้วยอุปมาอุปไมย (สมุดโทรศัพท์, ร้านอาหาร, ห้องสมุด) — เข้าใจง่ายแม้ไม่เคยใช้ MongoDB |
| **README.md ละเอียด** | มี quick start, access points, test commands, cleanup — ครบถ้วน |

### ✨ ผลลัพธ์

| ✅ สิ่งที่ใช้งานได้จริง | รายละเอียด |
|---|---|
| `sh.status()` | ✅ แสดง 2 shards active |
| `shardDistribution()` | ✅ 52/48 split บน 1,000 docs |
| HAProxy load balancing | ✅ กระจาย query ไป mongos ทั้ง 2 ตัว |
| Prometheus → Grafana | ✅ metrics flow ครบ pipeline |

---

## 🔴 สิ่งที่พัง — Timeline แห่งความล้มเหลว (What Went Wrong)

การ deploy จริงมีปัญหาเยอะกว่าที่คิด — ต่อไปนี้คือ **ทุกความล้มเหลว** เรียงตามลำดับเวลา:

### 🕐 Timeline

```
Day 1  ─── Deploy Attempt 1 ❌  mongod ทั้งหมด crash → ไม่มี keyfile
Day 1  ─── Deploy Attempt 2 ❌  coordinator init.sh บั๊ก → primary variable ว่าง
Day 1  ─── Deploy Attempt 3 ❌  mongos crash → command มี "mongos" ซ้ำ 2 ครั้ง
Day 1  ─── Deploy Attempt 4 ❌  coordinator rs.initiate() ไม่ได้ → localhost exception
Day 1  ─── Deploy Attempt 5 ❌  Prometheus exporters auth failed → monitor user ไม่ครบ
Day 1  ─── ✅ Manual init ผ่าน docker exec → cluster ทำงาน!
Day 2  ─── Grafana Import ❌ v1 API → 0 panels
Day 2  ─── Grafana Import ❌ v2 API → panels ขึ้นแต่ DS_PROMETHEUS ไม่ resolve
Day 2  ─── Grafana Import ❌ $env variable default ว่าง → queries กลับว่างหมด
Day 2  ─── ✅ แก้ UID + ตั้ง $env=.* → dashboard ใช้งานได้
Day 3  ─── Convert to multi-host → 3 docker-compose files + HAProxy + init scripts
```

---

### 🐛 แจกแจง Bug ทั้งหมด

| # | ความล้มเหลว | อาการ | Root Cause | Fix |
|---|---|---|---|---|
| 1 | **mongod crash — ไม่มี keyfile** | `mongod` ทั้ง 9 ตัว start ไม่ได้, log: `keyFile: /data/keyfile not found` | `mongod.conf` ตั้ง `authorization: enabled` + `keyFile` แต่ไม่มี container ไหนสร้าง keyfile ก่อน | เพิ่ม keyfile generation ใน coordinator + ให้ mongod entrypoint รอ keyfile จาก shared volume |
| 2 | **init_repset() — primary ว่าง** | `members[0]` เป็น empty string, `rs.initiate()` fail | ฟังก์ชันรับ `$rep_set` เป็น argument แรก แต่ไม่ได้ `shift` — `members` array มี `configdb` เป็น element แรก ทำให้ `primary="${members[0]}"` = `configdb` (ไม่ใช่ host:port) | เพิ่ม `shift` + `members=("$@")` ใน `init_repset()` |
| 3 | **mongos command ซ้ำ** | `docker logs` เห็น `"mongos" "mongos" --configdb ...` → mongos crash | `command:` ใน docker-compose.yml ระบุ `"mongos"` แต่ `ENTRYPOINT` ใน Dockerfile มี `mongos` อยู่แล้ว → โดน append ซ้ำ | ลบ `"mongos"` ออกจาก `command:` ใน compose |
| 4 | **mongos crash — ไม่มี keyFile** | mongos start ไม่ได้, log: `Unable to read keyFile` | mongos ต้องใช้ keyFile เหมือน mongod → compose ไม่ได้ mount keyfile volume ให้ mongos | เพิ่ม `keyFile: /data/keyfile` ใน mongos command + mount shared volume |
| 5 | **coordinator rs.initiate() ไม่ได้** | `rs.initiate()` วิ่งจาก coordinator container → MongoDB ปฏิเสธ | **localhost exception:** เมื่อ `authorization: enabled`, `rs.initiate()` รันได้จาก localhost ของ mongod เท่านั้น — coordinator เป็น separate container ไม่ใช่ localhost | ต้องใช้ `docker exec` จาก host machine → เพิ่ม `init-cluster.sh` ที่ SSH เข้า host แล้ว `docker exec` |
| 6 | **.env มี literal `***`** | `echo ${MONGO_PASSWORD}` → `***` จริง ๆ ไม่ใช่ password | ใช้ `sed 's/PASSWORD/***/'` แทน `sed 's/PASSWORD/newpassword/'` — ดันใช้ `***` เป็น replacement string | ตรวจสอบด้วย `xxd .env` หรือ `cat -A .env` → แก้ด้วยตนเอง |
| 7 | **monitor user ไม่ครบทุก shard** | Prometheus exporters ติดต่อ shard0, shard1 ไม่ได้ — authentication failed | สร้าง monitor user เฉพาะบน configdb → shard0/shard1 ไม่มี user นี้ | สร้าง monitor user บนทุก replica set primary (configdb + shard0 + shard1) |
| 8 | **Grafana v1 import → 0 panels** | import `dashboard-14997.json` ผ่าน `/api/dashboards/db` → dashboard สร้างแต่ไม่มี panels | dashboard อยู่ใน v2 JSON format — `/api/dashboards/db` (v1 API) แปลงไม่สมบูรณ์ | ใช้ v2 API: `POST /api/dashboards/import` |
| 9 | **DS_PROMETHEUS ไม่ resolve** | panels แสดง `Datasource not found` | dashboard ใช้ `${DS_PROMETHEUS}` — เป็นตัวแปรที่ Grafana resolve จาก datasource name แต่ชื่อต้อง match เป๊ะ | แก้ไข JSON: แทนที่ `${DS_PROMETHEUS}` ด้วย UID จริง `efrc81l8a9logd` |
| 10 | **$env variable default ว่าง** | ทุก panel แสดง "No data" | dashboard มี template variable `$env` ที่ default ว่าง → queries ไม่ match อะไรเลย | ตั้ง default เป็น `.*` (match ทุก environment) |

---

## 🔍 การวิเคราะห์สาเหตุราก (Root Cause Analysis)

### 🧠 สาเหตุเชิงระบบ (ไม่ใช่แค่ bug เดี่ยว ๆ)

| # | Root Cause | Impact | อธิบาย |
|---|---|---|---|
| **RC1** | **Coordinator init.sh ถูกสร้างโดย AI แต่ไม่เคยทดสอบ** | 🔴🔴🔴 | บั๊ก 2 จุดในไฟล์เดียว — `shift` หาย + `host:$port` url ผิด — ถ้ามีการเทสต์สัก 1 ครั้งบน Docker local จะเจอทันที |
| **RC2** | **ไม่เข้าใจ MongoDB security model** | 🔴🔴 | `localhost exception` คือ fundamental security feature ของ MongoDB — ถ้ารู้ก่อนตั้งแต่ต้น จะออกแบบ init flow ต่างออกไป (หรือใช้ `docker exec` ตั้งแต่แรก) |
| **RC3** | **ไม่มี integration test** | 🔴🔴🔴 | ไม่มี environment สำหรับทดสอบ cluster จริงก่อน push — `docker compose up` ทุกครั้งคือ "production test" ซึ่งใช้เวลานานและเจ็บปวด |
| **RC4** | **sed ผิด syntax** | 🔴 | `.env` ถูกแก้ด้วย `sed` แบบผิด — ใช้ `***` (placeholder) แทนค่าใหม่ — ง่ายเกินกว่าจะเกิดขึ้นถ้าใช้ `cat -A` เช็ค |
| **RC5** | **Grafana API version incompatibility** | 🔴🔴 | dashboard JSON เป็น v2 format แต่ import ผ่าน v1 API — ความไม่เข้ากันนี้ไม่ถูก document ชัดเจน → ลองผิดลองถูก |
| **RC6** | **Multi-host: initial architecture ใช้ Docker DNS** | 🟡 | Docker DNS (`configdb-replica0:27017`) ใช้ได้แค่ single-host → พอเปลี่ยนเป็น multi-host ต้อง rewrite การอ้างอิงทั้งหมดเป็น IP จริง |

### 📊 Impact Matrix

```
                    ความถี่ (เกิดบ่อยแค่ไหน?)
                    สูง              ต่ำ
              ┌──────────────┬──────────────┐
ผลกระทบ สูง   │ RC1, RC3     │ RC2          │
              │ (ทุก deploy) │ (init ครั้งแรก)│
              ├──────────────┼──────────────┤
ผลกระทบ ต่ำ   │ RC6          │ RC4, RC5     │
              │ (multi-host) │ (once-off)   │
              └──────────────┴──────────────┘
```

---

## 💡 บทเรียนที่ได้ (Lessons Learned)

### 📌 Lesson 1: **Init scripts ต้องทดสอบบนคลัสเตอร์จริงก่อน commit**

> *"If it wasn't tested, it doesn't work."*

- เสียเวลา **5 deploy attempts** เพราะ init.sh มี 2 bugs — ทั้งคู่จับได้ในการทดสอบ 5 นาที
- **Action:** หลังจากนี้ — ทุก init script ต้องมี `docker compose up && ./test-init.sh` ก่อน merge

### 📌 Lesson 2: **MongoDB auth + keyfile = chicken-and-egg — `docker exec` คือทางออก**

```
MongoDB: เปิด auth → ต้องมี user ก่อน → แต่สร้าง user ต้องเชื่อมต่อก่อน → แต่เชื่อมต่อต้อง auth → ...
```

ทางออกของ MongoDB คือ **localhost exception** — คำสั่ง `rs.initiate()` และ `db.createUser()` ครั้งแรก **ต้องรันจาก localhost เท่านั้น**

- ❌ container A → container B (ไม่ใช่ localhost)
- ✅ `docker exec container-B mongosh ...` (คือ localhost)

### 📌 Lesson 3: **ตรวจสอบ `.env` ด้วย `xxd` หรือ `cat -A` — ไม่ใช่ `cat` เปล่า**

```
$ cat .env
MONGO_PASSWORD=***        ← ดูเผิน ๆ เหมือน password ถูก mask

$ cat -A .env
MONGO_PASSWORD=***$       ← คือ *** จริง ๆ นะ!
```

### 📌 Lesson 4: **Grafana dashboard JSON — resolve datasource UID ก่อน import**

- `${DS_PROMETHEUS}` ใช้ได้เฉพาะตอน import ผ่าน UI (Grafana จะถามให้เลือก datasource)
- Import ผ่าน API → ต้องใช้ UID จริง
- **Best practice:** ใช้ provisioning (`grafana/datasources/`) ให้ datasource มี UID ที่คาดเดาได้ → ใส่ UID นั้นใน dashboard JSON ตั้งแต่แรก

### 📌 Lesson 5: **Multi-host = ใช้ IP จริง, ไม่ใช่ Docker DNS**

| Single-host | Multi-host |
|---|---|
| `configdb-replica0:27017` (Docker DNS) | `10.0.0.1:27017` (IP จริง) |
| containers คุยกันผ่าน Docker network | containers คุยกันผ่าน network จริง |
| service name = hostname | IP = hostname |

**ข้อดีของ IP จริง:** port 27017 ใช้ซ้ำได้ทุก host (คนละ IP → ไม่ชน)

### 📌 Lesson 6: **Separate docker-compose ต่อ host ดีกว่า Docker Swarm สำหรับ <5 hosts**

| Docker Swarm | Separate docker-compose |
|---|---|
| ต้อง setup Swarm cluster | แค่ `docker compose up` |
| Config ซับซ้อน (overlay network, secrets) | Config ตรงไปตรงมา |
| เหมาะกับ ≥5 hosts, auto-healing | เหมาะกับ 2-4 hosts, manual control |

เราเลือก separate compose — ถูกต้องสำหรับ use case นี้

### 📌 Lesson 7: **`x-` prefix ใน docker compose ไม่ได้ป้องกัน service creation เสมอ**

เราใช้ `x-mongo-exporter-base` เป็น YAML anchor สำหรับ reuse config — แต่มันถูก Docker Compose ตีความเป็น service จริงในบาง version → ต้องลบออกและ copy-paste config แทน

### 📌 Lesson 8: **อย่าเชื่อ ENTRYPOINT ของ base image — เช็คก่อน**

mongos base image มี `ENTRYPOINT ["mongos"]` → การใส่ `"mongos"` ใน `command:` ทำให้กลายเป็น `mongos mongos --configdb ...` → crash

**Rule:** เช็ค `docker inspect <image>` หรือ `docker history` ก่อน override command

---

## 📊 By the Numbers (ตัวเลข)

| หมวด | จำนวน |
|---|---|
| **Commits ทั้งหมด** | 12 |
| **ไฟล์ทั้งหมดใน repo** | 22 |
| **ไฟล์ที่สร้างใหม่** | 10 (Dockerfiles, configs, scripts, docs) |
| **ไฟล์ที่แก้ไขจากต้นฉบับ** | 3 (prometheus.yml, docker-compose.yml, dashboard-14997.json) |
| **ไฟล์ที่เพิ่มใน multi-host conversion** | 6 (3 compose + keyfile script + init script + haproxy config) |
| **Bugs ที่พบทั้งหมด** | 10 |
| **Deploy attempts ก่อนสำเร็จ** | 5 |
| **Containers (single-host)** | 26 |
| **Containers ต่อ host (multi-host)** | ~12-15 |
| **MongoDB version** | 8.2.11 |
| **RAM ที่ใช้ (single-host)** | ~4-5 GB |
| **Replica Sets** | 3 (configdb, shard0, shard1) |
| **Shards** | 2 |
| **Mongos Routers** | 2 |
| **Prometheus Targets** | 12 (9 exporters + 2 node-exporters + 1 prometheus) |

---

## 🎯 ถ้าได้ทำใหม่อีกครั้ง — จะทำอะไรต่างไป (What We'd Do Differently)

### 🔄 ลำดับการพัฒนาที่ถูกต้อง (Retrospective)

| ❌ สิ่งที่ทำจริง | ✅ ควรทำแบบนี้ |
|---|---|
| เขียน init.sh → commit → deploy → เจอบั๊ก → แก้ → deploy → เจอบั๊ก → ... | เขียน init.sh → **test บน Docker local** → commit → deploy |
| deploy ทุกอย่างพร้อมกัน (9 mongod + mongos + coordinator) | แบ่ง deploy เป็น **3 phases**: (1) mongod only → (2) rs.initiate ผ่าน docker exec → (3) mongos + users |
| import Grafana dashboard ทีหลัง | ตั้งค่า datasource provisioning + embed UID ใน dashboard JSON ตั้งแต่แรก |
| ใช้ Docker DNS อ้างอิงทุกที่ | ออกแบบให้ใช้ IP จริงตั้งแต่แรก (หรือใช้ environment variables `${HOST_IP}:PORT`) |
| ไม่มี smoke test | เขียน `test-cluster.sh` ง่าย ๆ: `sh.status()` → `insert 100 docs` → `shardDistribution()` → check split |

### 🧪 Checklist ก่อน Deploy

- [ ] `docker compose up` บนเครื่อง dev → ทุก container เป็น `healthy`
- [ ] `rs.initiate()` ทำงานได้ผ่าน `docker exec` (ไม่ผ่าน coordinator)
- [ ] `sh.status()` แสดง shards ทั้งหมด active
- [ ] `shardDistribution()` แสดง split ≈ 50/50
- [ ] `.env` ผ่านการตรวจสอบด้วย `cat -A` หรือ `xxd`
- [ ] Grafana dashboard import ผ่าน API → panels แสดงข้อมูล
- [ ] Prometheus targets ทั้งหมด → `UP`

---

## 📝 สรุปส่งท้าย

นี่คือโปรเจกต์ที่ **"เกือบจะดีตั้งแต่ครั้งแรก"** — สถาปัตยกรรมถูกต้อง, โค้ดส่วนใหญ่ใช้ได้, แต่ **รายละเอียดปลีกย่อย** ที่ไม่ได้ทดสอบกลับกลายเป็นปัญหาใหญ่

**สิ่งที่เราได้เรียนรู้สำคัญที่สุด:**

> 🎯 **"Test what you build, not what you think you built."**
> — ถ้า init.sh ถูกทดสอบแค่ 1 ครั้งก่อน commit — 5 deploy attempts จะเหลือแค่ 1

โปรเจกต์นี้จบด้วยความสำเร็จ — MongoDB Sharded Cluster ทำงานได้, sharding กระจายข้อมูลถูกต้อง, monitoring ใช้งานได้จริง — แต่เส้นทางกว่าจะถึงจุดนั้น **เต็มไปด้วยบทเรียนที่ควรค่าแก่การจดจำ**

---

*📅 Post-mortem วันที่: 7 กรกฎาคม 2026*
*📦 Repository: [mongodb-cluster-shard-docker](https://github.com/Wsangsrichan/mongodb-cluster-shard-docker)*
*🖊️ Language: ไทย (Thai)*
