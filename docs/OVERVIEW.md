# 🍃 MongoDB Sharded Cluster — เข้าใจคลัสเตอร์ MongoDB แบบกระจายศูนย์ (สำหรับมือใหม่)

[![ภาษาไทย](https://img.shields.io/badge/ภาษา-ไทย-blue)](.)
[![Level](https://img.shields.io/badge/ระดับ-เริ่มต้น-green)](.)

---

เอกสารนี้ถูกเขียนขึ้นสำหรับคนที่ **ไม่เคยรู้จัก MongoDB clustering มาก่อนเลย** เราจะค่อย ๆ อธิบายตั้งแต่พื้นฐาน ไล่ขึ้นไปจนถึงการทำงานจริงของคลัสเตอร์ในโปรเจกต์นี้ ทุกหัวข้อจะใช้การเปรียบเทียบ (อุปมาอุปไมย) กับสิ่งของในชีวิตจริง เพื่อให้เข้าใจง่ายที่สุด

---

## 🏠 MongoDB คืออะไร

ลองนึกภาพว่าเรามี **ตู้เก็บเอกสารดิจิทัล** แทนที่จะเก็บข้อมูลเป็นตารางแบบ Excel (แบบ SQL) MongoDB เก็บข้อมูลในรูปแบบ **เอกสาร (Document)** ที่คล้ายกับไฟล์ JSON — มันคือกระดาษแผ่นหนึ่งที่เขียนข้อมูลไว้อย่างอิสระ ไม่ต้องมีโครงสร้างตายตัว

```
┌──────────────────────────────────────┐
│  MongoDB = ตู้เก็บเอกสารดิจิทัล       │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ {                              │  │
│  │   "ชื่อ": "สมชาย",             │  │  ← 1 Document
│  │   "อายุ": 30,                  │  │
│  │   "ที่อยู่": "กรุงเทพฯ",       │  │
│  │   "งานอดิเรก": ["อ่าน","วิ่ง"] │  │
│  │ }                              │  │
│  └────────────────────────────────┘  │
│  ┌────────────────────────────────┐  │
│  │ { "ชื่อ": "สมหญิง", ... }      │  │  ← อีก 1 Document
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

- **SQL** → ข้อมูลต้องจัดเป็นแถว-คอลัมน์ เหมือนสมุดบัญชี
- **MongoDB** → ข้อมูลยืดหยุ่น เหมือนกระดาษโน้ตที่เขียนอะไรก็ได้

---

## 📋 Replica Set — สำเนาข้อมูลอัตโนมัติ

### อุปมาอุปไมย: เครื่องถ่ายเอกสาร 3 เครื่อง

ลองนึกภาพห้องทำงานที่มีเครื่องถ่ายเอกสาร 3 เครื่อง:

- **เครื่องที่ 1 (PRIMARY)** — เครื่องเจ้านาย รับเอกสารต้นฉบับ (คำสั่งเขียนข้อมูล) เท่านั้น
- **เครื่องที่ 2 (SECONDARY)** — เครื่องสำเนา คอยถ่ายเอกสารตามเครื่องที่ 1
- **เครื่องที่ 3 (SECONDARY)** — เครื่องสำเนาอีกเครื่อง ถ่ายตามเครื่องที่ 1 เหมือนกัน

ถ้าเครื่องเจ้านาย (PRIMARY) พัง — ลูกน้องคนใดคนหนึ่ง (SECONDARY) จะลุกขึ้นเป็นเจ้านายคนใหม่ **อัตโนมัติ**

```
[คุณเขียนข้อมูล]  →  [PRIMARY 📝]  → sync → [SECONDARY 1 📋]
                                  → sync → [SECONDARY 2 📋]

         ⚡ ถ้า PRIMARY พัง ⚡

            [SECONDARY 1 📋]  เลื่อนขั้น → [PRIMARY คนใหม่ 👑]
            [SECONDARY 2 📋]  sync ตาม PRIMARY คนใหม่
```

### จุดสำคัญ

| บทบาท | หน้าที่ |
|--------|--------|
| **PRIMARY** | รับคำสั่งเขียนข้อมูล (insert/update/delete) เท่านั้น |
| **SECONDARY** | อ่านข้อมูลได้ แต่ **เขียนไม่ได้** — เป็นแค่สำเนา |
| **ARBITER** (ไม่มีในโปรเจกต์นี้) | กรรมการโหวต ไม่เก็บข้อมูล |

- **3 replicas = จำนวนขั้นต่ำสำหรับ production** เพราะถ้ามี 2 ตัว พอตัวนึงตาย อีกตัวจะไม่รู้ว่าใครควรเป็น PRIMARY (ไม่มีเสียงข้างมาก — ต้อง ≥2 ใน 3 ถึงจะชนะโหวต)
- การเลือก PRIMARY ใหม่เรียกว่า **Election** — ใช้เวลาไม่กี่วินาที

> 💡 **ในโปรเจกต์นี้:** เรามี 3 Replica Sets (configdb, shard0, shard1) แต่ละชุดมี 3 replicas รวมทั้งหมด 9 mongod nodes

---

## 🗂️ Sharding — แบ่งข้อมูลเป็นชิ้น ๆ

### อุปมาอุปไมย: สมุดโทรศัพท์ที่หนักเกินไป

สมุดโทรศัพท์เล่มใหญ่ที่มี 1,000,000 เบอร์ หนักจนคนเดียวถือไม่ไหว เราจึงฉีกแบ่งเป็น 2 เล่ม:

```
┌──────────────────────────────────────────────────────────┐
│                 สมุดโทรศัพท์ 1,000,000 เบอร์              │
│                                                          │
│   ┌──────────────────────┐    ┌──────────────────────┐   │
│   │   เล่ม 1: A → M      │    │   เล่ม 2: N → Z      │   │
│   │   (พนักงานคนที่ 1)    │    │   (พนักงานคนที่ 2)    │   │
│   └──────────────────────┘    └──────────────────────┘   │
│            ↑                          ↑                  │
│            └──────────┬───────────────┘                  │
│                       │                                  │
│               [พนักงานต้อนรับ]                             │
│               "คุณถามหาเบอร์อะไรครับ?"                     │
│               "เบอร์คุณสมชาย → ไปที่เล่ม 1"                │
└──────────────────────────────────────────────────────────┘
```

### Sharding ใน MongoDB

- **Shard** = 1 Replica Set ที่เก็บข้อมูลแค่ส่วนหนึ่ง (subset) ของข้อมูลทั้งหมด
- **Shard Key** = ฟิลด์ที่ใช้ตัดสินว่าจะส่งข้อมูลไป Shard ไหน (เหมือนอักษรตัวแรกของชื่อ)
- **Chunk** = กลุ่มย่อยของข้อมูลในแต่ละ Shard (เหมือนแบ่งสมุดโทรศัพท์เป็นกลุ่ม A-E, F-J, …)

### Hashed Sharding vs Range Sharding

```
HASHED (กระจายเท่า ๆ กัน — โปรเจกต์นี้ใช้วิธีนี้)
─────────────────────────────────────────────────
ชื่อ → hash("สมชาย") → 819273645 → Shard 1
ชื่อ → hash("สมหญิง") → 472819365 → Shard 0

ข้อดี: ข้อมูลกระจายสมํ่าเสมอ ไม่มี Shard ไหนหนักเป็นพิเศษ

RANGE (แบ่งตามช่วง — ใช้เมื่อข้อมูลมีลําดับชัดเจน)
─────────────────────────────────────────────────
Customer ID 0001–5000 → Shard 0
Customer ID 5001–9999 → Shard 1

ข้อดี: ค้นหาข้อมูลต่อเนื่องได้เร็ว แต่เสี่ยง Shard ไม่สมดุล
```

> 💡 **ในโปรเจกต์นี้:** เราใช้ **Hashed Sharding** บน `_id` เพื่อให้ข้อมูลกระจายเท่า ๆ กันทั้ง 2 Shards

---

## 🗺️ Config Server — สารบัญของคลัสเตอร์

### อุปมาอุปไมย: แผนที่ / ดัชนีของห้องสมุด

ลองนึกภาพ **ห้องสมุดขนาดใหญ่** ที่มีหนังสือกระจายไปตามชั้นต่าง ๆ เราจะรู้ได้อย่างไรว่าหนังสือ "แฮร์รี่ พอตเตอร์" อยู่ชั้นไหน? — ต้องดูที่ **บัตรดัชนี (Card Catalog)** ตรงกลาง

```
┌─────────────────────────────────────────────────────┐
│                  ห้องสมุดกลาง                        │
│                                                     │
│   ┌─────────────────────┐                           │
│   │  Config Server      │  ← "บัตรดัชนีของห้องสมุด"  │
│   │  (สารบัญ คลัสเตอร์)   │                           │
│   │                     │                           │
│   │  • "ข้อมูลลูกค้า     │                           │
│   │     #5432  → Shard 1│                           │
│   │    Replica 2"       │                           │
│   │                     │                           │
│   │  • "ข้อมูลสินค้า    │                           │
│   │    #1001  → Shard 0 │                           │
│   │    Replica 0"       │                           │
│   └─────────────────────┘                           │
│                                                     │
│   Config Server เก็บ:                                │
│   - Chunk ไหนอยู่ Shard ไหน                           │
│   - Shard ไหนมีกี่ Chunk                              │
│   - ข้อมูล metadata ทั้งหมดของคลัสเตอร์               │
└─────────────────────────────────────────────────────┘
```

Config Server คือ **มันสมองของคลัสเตอร์** — มันรู้ว่าข้อมูลทุกชิ้นอยู่ที่ไหน ถ้า Config Server พัง = คลัสเตอร์ใช้ไม่ได้

> 💡 **ในโปรเจกต์นี้:** Config Server มี 3 replicas (configdb-replica0/1/2) เพื่อให้ทนทานต่อความล้มเหลว

---

## 🚦 Mongos Router — พนักงานต้อนรับ

### อุปมาอุปไมย: พนักงานต้อนรับที่โรงแรมใหญ่

คุณเดินเข้าโรงแรมใหญ่ที่มี 200 ห้อง อยากเช็คอิน คุณไม่เดินหาห้องเอง — คุณไปหา **พนักงานต้อนรับ (Receptionist)** ที่เคาน์เตอร์

```
┌──────────────────────────────────────────────────────────┐
│                        โรงแรมใหญ่                          │
│                                                          │
│   คุณ: "ผมจองห้อง 1003 ไว้ครับ"                           │
│              │                                           │
│              ▼                                           │
│   ┌──────────────────────┐                               │
│   │ 🧑‍💼 พนักงานต้อนรับ     │  ← Mongos Router              │
│   │   (Mongos)           │                               │
│   │                      │                               │
│   │ "ห้อง 1003... อ๋อ     │                               │
│   │  อยู่ตึก B ชั้น 3      │                               │
│   │  ไปทางนั้นเลยครับ"    │                               │
│   └──────┬───────────────┘                               │
│          │                                               │
│    ┌─────┴─────┐                                         │
│    ▼           ▼                                         │
│  ตึก A       ตึก B    ← Shards                           │
│ (Shard 0)  (Shard 1)                                     │
└──────────────────────────────────────────────────────────┘
```

### Mongos ทำอะไรบ้าง

- **รับ query จาก client** — คุณไม่ต้องรู้ว่าข้อมูลอยู่ Shard ไหน
- **ถาม Config Server** — "ข้อมูลนี้อยู่ Shard ไหนนะ?"
- **ส่ง query ไปยัง Shard ที่ถูกต้อง**
- **รวมผลลัพธ์** (ถ้าข้อมูลมาจากหลาย Shard) แล้วส่งกลับให้ client

Mongos คือ **ประตูทางเข้าเดียว** ที่ client ใช้คุยกับคลัสเตอร์ — client ไม่เคยคุยกับ Shard โดยตรง

> 💡 **ในโปรเจกต์นี้:** มี 2 Mongos Routers (พอร์ต 27017 และ 27018) — เผื่อตัวนึงพัง อีกตัวยังทำงานได้

---

## 🏗️ สถาปัตยกรรมรวม — ภาพใหญ่ทั้งหมด

นี่คือสถาปัตยกรรมของคลัสเตอร์ในโปรเจกต์นี้:

```
                          ┌─────────────────────────┐
                          │   👤 คุณ (Client/Mongosh) │
                          └───────────┬─────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
                    ▼                                   ▼
          ┌─────────────────┐                 ┌─────────────────┐
          │ Mongos Router 0 │                 │ Mongos Router 1 │
          │   (🧑‍💼 พนง.ต้อนรับ) │                 │   (🧑‍💼 พนง.ต้อนรับ) │
          │   พอร์ต 27017    │                 │   พอร์ต 27018    │
          └────────┬────────┘                 └────────┬────────┘
                   │                                   │
                   │           ┌───────────────────────┘
                   │           │
    ┌──────────────┼───────────┼──────────────┐
    │              │           │              │
    ▼              ▼           ▼              ▼
┌────────┐   ┌─────────┐  ┌─────────┐   ┌─────────┐
│Config  │   │ Shard 0 │  │ Shard 1 │   │ Monitoring│
│Server  │   │  (RS)   │  │  (RS)   │   │          │
│ (RS)   │   │         │  │         │   │Prometheus│
│        │   │┌───────┐│  │┌───────┐│   │ :9090    │
│┌──────┐│   ││Rep 0  ││  ││Rep 0  ││   │          │
││Rep 0 ││   │├───────┤│  │├───────┤│   │ Grafana  │
│├──────┤│   ││Rep 1  ││  ││Rep 1  ││   │ :3000    │
││Rep 1 ││   │├───────┤│  │├───────┤│   └─────────┘
│├──────┤│   ││Rep 2  ││  ││Rep 2  ││
││Rep 2 ││   │└───────┘│  │└───────┘│
│└──────┘│   └─────────┘  └─────────┘
│  3 reps │
│ metadata│
└────────┘
```

### จำนวน Containers ทั้งหมดในโปรเจกต์นี้

| องค์ประกอบ | จำนวน | หน้าที่ |
|-----------|------|--------|
| Config Server replicas | 3 | เก็บ metadata ของคลัสเตอร์ |
| Shard 0 replicas | 3 | เก็บข้อมูลส่วนที่ 1 |
| Shard 1 replicas | 3 | เก็บข้อมูลส่วนที่ 2 |
| Mongos Routers | 2 | รับ query จาก client |
| Coordinator | 1 | สร้าง keyfile + รอโหนดพร้อม |
| Backup Service | 1 | สำรองข้อมูลอัตโนมัติทุกวัน |
| MongoDB Exporters | 11 | ส่ง metrics ให้ Prometheus |
| Prometheus | 1 | เก็บ metrics |
| Grafana | 1 | แสดงผล dashboard |
| **รวม** | **26 containers** |

---

## 🚀 วิธีติดตั้งและใช้งานทีละขั้น

> ⚠️ **ก่อนเริ่ม:** ต้องมี Docker 20.10+ และ Docker Compose v2+ ติดตั้งแล้ว RAM อย่างน้อย 4-5 GB

### ขั้นตอนที่ 1: Clone โปรเจกต์และตั้งค่า .env

```bash
git clone https://github.com/Wsangsrichan/mongodb-cluster-shard-docker.git
cd mongodb-cluster-shard-docker
cp .env.example .env
```

แก้ไขไฟล์ `.env` ตั้งรหัสผ่านให้แข็งแรง:

```env
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=ตั้งรหัสผ่านที่คาดเดายาก
MONGO_MONITOR_USER=monitor
MONGO_MONITOR_PASSWORD=ตั้งรหัสผ่านอีกอัน
```

### ขั้นตอนที่ 2: Start containers ทั้งหมด

```bash
docker compose up -d --build
```

**เกิดอะไรขึ้นเบื้องหลัง?**
- Docker สร้าง 9 mongod nodes (3 ConfigDB + 3 Shard0 + 3 Shard1)
- สร้าง 2 Mongos Routers
- Coordinator container เริ่มทำงาน: สร้าง keyfile → รอทุกโหนดพร้อม → ตั้งค่า replica sets → เพิ่ม shards → สร้าง users
- Prometheus + Grafana + Exporters เริ่มเก็บ metrics

### ขั้นตอนที่ 3: รอให้โหนดพร้อม

```bash
sleep 30
```

ตรวจสอบว่าทุก container ทำงานอยู่:

```bash
docker compose ps
```

### ขั้นตอนที่ 4: Initialize Replica Sets (ทำมือ)

> ⚠️ **ทำไมต้องทำมือ?** — MongoDB มีกลไกที่เรียกว่า **localhost exception** เมื่อเปิด `authorization: enabled` ไว้ คำสั่ง `rs.initiate()` จะถูกรันได้จาก localhost เท่านั้น Coordinator container ไม่ใช่ localhost ของ mongod จึงรันให้ไม่ได้ เราจึงต้องใช้ `docker exec` (ซึ่งรันในฐานะ localhost) แทน

**Init Config Server:**

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

**Init Shard 0:**

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

**Init Shard 1:**

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

### ขั้นตอนที่ 5: รอ Election เลือก PRIMARY

```bash
sleep 15
```

ลองเช็คดูว่าแต่ละ Replica Set มี PRIMARY แล้วหรือยัง:

```bash
docker exec mongodb-cluster-shard-docker-configdb-replica0-1 mongosh --quiet --eval \
  "rs.status().members.map(m => ({name: m.name, stateStr: m.stateStr}))"
```

Output ควรแสดง `PRIMARY` 1 ตัว และ `SECONDARY` 2 ตัว

### ขั้นตอนที่ 6: สร้าง Admin Users บนแต่ละ Replica Set

เนื่องจากเราเปิด authentication ไว้ เราต้องสร้าง users ก่อนที่ Mongos จะเชื่อมต่อได้

```bash
# Config Server
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

### ขั้นตอนที่ 7: สร้าง Monitor User (ให้ Prometheus ใช้)

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

### ขั้นตอนที่ 8: เพิ่ม Shards เข้าคลัสเตอร์

ตอนนี้ Mongos routers มี users ให้ยืนยันตัวตนแล้ว:

```bash
docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "
sh.addShard('shard0/shard0-replica0:27017,shard0-replica1:27017,shard0-replica2:27017')"

docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "
sh.addShard('shard1/shard1-replica0:27017,shard1-replica1:27017,shard1-replica2:27017')"
```

### ขั้นตอนที่ 9: ตรวจสอบคลัสเตอร์

```bash
docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "sh.status()"
```

ควรเห็นทั้ง 2 shards ที่ `state: 1` (active) 🎉

---

## 🔍 ทดสอบว่า Sharding ทำงานจริง

เราจะสร้างฐานข้อมูลทดสอบ เปิด sharding และใส่ข้อมูล 1000 records เพื่อดูการกระจายตัว:

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

### วิธีอ่านผลลัพธ์

Output จะประมาณนี้:

```
Shard shard0 at shard0/shard0-replica0:27017,...
 data : 48.2 KiB docs : 512 chunks : 2
 estimated data per chunk : 24.1 KiB

Shard shard1 at shard1/shard1-replica0:27017,...
 data : 46.8 KiB docs : 488 chunks : 2
 estimated data per chunk : 23.4 KiB
```

**คำอธิบาย:**

| ค่า | ความหมาย |
|-----|---------|
| `data` | ปริมาณข้อมูลใน Shard นี้ |
| `docs` | จำนวนเอกสาร (documents) ใน Shard นี้ |
| `chunks` | จำนวน chunks — กลุ่มข้อมูลย่อย |
| `estimated data per chunk` | ขนาดเฉลี่ยต่อ chunk |

ถ้า docs ของทั้ง 2 shards ใกล้เคียงกัน (เช่น 512 และ 488) — แสดงว่า **Hashed Sharding ทำงานถูกต้อง** ✅

### เช็ค chunks โดยละเอียด

```bash
docker exec mongodb-cluster-shard-docker-mongos-router0-1 mongosh --quiet \
  -u admin -p YOUR_PASSWORD --authenticationDatabase admin --eval "
use config;
db.chunks.find({ns: 'testdb.testcoll'}).toArray()
"
```

---

## 📊 Monitoring — กล้องวงจรปิดของคลัสเตอร์

### อุปมาอุปไมย: กล้องวงจรปิดในห้างสรรพสินค้า

```
┌───────────────────────────────────────────────────┐
│                  ห้างสรรพสินค้า                     │
│                                                   │
│   📹 กล้องวงจรปิด → มองเห็นทุกซอกทุกมุม             │
│   ├── ประตูทางเข้า (Mongos): มีคนเข้า 100 คน/นาที   │
│   ├── ชั้น 1 (Shard 0): ใช้งาน 60%                 │
│   └── ชั้น 2 (Shard 1): ใช้งาน 55%                 │
│                                                   │
│   📺 ห้องควบคุม (Grafana) → แสดงผลผ่านจอใหญ่        │
│   💾 เครื่องบันทึก (Prometheus) → เก็บบันทึกย้อนหลัง │
└───────────────────────────────────────────────────┘
```

- **Prometheus** = เครื่องบันทึกกล้องวงจรปิด — เก็บ metrics ทุก ๆ วินาที
- **Grafana** = จอมอนิเตอร์ในห้องควบคุม — แสดงข้อมูลเป็นกราฟสวย ๆ
- **MongoDB Exporters** = ตัวแปลงสัญญาณจาก MongoDB → ภาษาที่ Prometheus เข้าใจ (มี 11 ตัว ครอบคลุมทุกโหนด)

### วิธีเข้าใช้งาน

| บริการ | URL | Username/Password |
|--------|-----|-------------------|
| **Grafana** | http://localhost:3000 | `admin` / `admin` |
| **Prometheus** | http://localhost:9090 | ไม่มี (เปิด public) |
| **Mongos Router 0** | `localhost:27017` | ใช้ mongosh connect |
| **Mongos Router 1** | `localhost:27018` | ใช้ mongosh connect |

### ตั้งค่า Grafana Dashboard

1. เปิด http://localhost:3000 → Login `admin/admin`
2. **Connections → Data Sources → Add data source → Prometheus**
3. URL: `http://prometheus:9090` → ชื่อ: `Prometheus` → Save & Test
4. **Dashboards → New → Import** → อัปโหลด `grafana/dashboard-14997.json`
5. เลือก Data Source เป็น `Prometheus` → Import

---

## 💾 Backup — สำรองข้อมูลอัตโนมัติ

Backup container ทำงานวนลูป ตรวจสอบเวลาทุก ๆ 30 วินาที พอถึงเวลาที่กำหนด (ค่าเริ่มต้น 01:00 UTC) จะรัน `mongodump` โดยอัตโนมัติ

```
┌───────────────────────────────────────────┐
│   Backup Service                          │
│                                           │
│   ทุก 01:00 UTC → mongodump               │
│   ├── บีบอัดด้วย gzip                      │
│   ├── เก็บใน container: /tmp/backups/      │
│   └── ก๊อปปี้ไป host: ./backups/           │
│                                           │
│   🧹 ลบ backups เก่าเกิน 7 วันโดยอัตโนมัติ  │
└───────────────────────────────────────────┘
```

**ตั้งค่าใน `.env`:**
- `BACKUP_TIME` — เวลาที่จะ backup (default: `01:00`)
- `BACKUP_RETENTION_DAYS` — เก็บย้อนหลังกี่วัน (default: `7`)

**รัน backup ทันที (manual):**

```bash
docker exec mongodb-cluster-shard-docker-backup-1 mongodump \
  --uri="mongodb://admin:YOUR_PASSWORD@mongos-router0:27017/admin?authSource=admin" \
  --out="/tmp/backups/manual_$(date +%Y%m%d_%H%M%S)" --gzip
```

---

## ⚠️ ข้อควรระวัง (Gotchas)

### 1. ทำไมต้องมี 3 replicas (อย่างน้อย)

MongoDB ใช้ระบบ **majority vote** (เสียงข้างมาก) ในการเลือก PRIMARY:

```
2 replicas → พัง 1 ตัว เหลือ 1 ตัว → ไม่มีเสียงข้างมาก (1 ใน 2) → ❌ หยุดทำงาน
3 replicas → พัง 1 ตัว เหลือ 2 ตัว → เสียงข้างมาก (2 ใน 3) → ✅ ทำงานต่อได้
```

### 2. Shard Key คือหัวใจของ Sharding

เลือก Shard Key ผิด = ข้อมูลไม่กระจาย, บาง Shard หนัก, ความเร็วตก

```
Shard Key แย่    →  { country: 1 }     → ข้อมูลประเทศเดียวกองอยู่ Shard เดียว
Shard Key ดี     →  { _id: "hashed" }  → ข้อมูลกระจายเท่า ๆ กันทุก Shard
```

### 3. Localhost Exception คืออะไร

MongoDB มีกฎความปลอดภัย: เมื่อเปิด `authorization: enabled` — คำสั่ง `rs.initiate()` (สร้าง Replica Set ครั้งแรก) จะรันได้จาก **localhost เท่านั้น** นี่คือเหตุผลที่เราต้องใช้ `docker exec` แทนที่จะให้ Coordinator container รันให้

### 4. Memory Usage

คลัสเตอร์นี้ใช้ RAM **4-5 GB** เป็นค่าเริ่มต้น — เพราะ MongoDB cache ข้อมูลไว้ใน RAM เพื่อความเร็ว ถ้าเครื่องมี RAM น้อย อาจต้องลดจำนวน replicas หรือปิดบาง services

### 5. เครือข่ายภายใน

ทุก container สื่อสารกันผ่าน Docker network ชื่อ `internalnetwork` — client เข้าถึงได้ผ่านพอร์ตที่ expose ไว้เท่านั้น (27017, 27018, 3000, 9090)

---

## 🎯 สรุป — ภาษาชาวบ้าน

ลองนึกภาพว่าคุณเปิด **ร้านอาหารขนาดใหญ่** ที่มีลูกค้าเยอะมาก:

- **MongoDB** คือครัวกลาง — ทุกอย่างเริ่มที่นี่
- **Shard 0 และ Shard 1** คือครัว 2 ห้องที่แยกกันทำงาน — ห้องนึงทำอาหารไทย อีกห้องทำอาหารฝรั่ง (หรือจะให้ทำคละ ๆ กันก็ได้)
- **Replica Set** คือการที่แต่ละครัวมี **กุ๊ก 3 คน** — คนนึงเป็นหัวหน้า (PRIMARY) อีก 2 คนเป็นผู้ช่วย คอยทำตามสูตรเดียวกันเป๊ะ ๆ ถ้าหัวหน้าลาป่วย ผู้ช่วยคนนึงเลื่อนเป็นหัวหน้าทันที ครัวไม่หยุด
- **Mongos Router** คือ **พนักงานรับออเดอร์** — ลูกค้าสั่งอะไร พนักงานรู้ว่าต้องส่งไปครัวไหน
- **Config Server** คือ **แผนผังร้าน** — บอกว่าอาหารแต่ละเมนูทำในครัวไหน เก็บอุปกรณ์อะไรบ้าง
- **Prometheus + Grafana** คือ **กล้องวงจรปิด** เห็นทุกอย่างว่าใครเข้าออก ครัวไหนยุ่งแค่ไหน

พอทุกอย่างประกอบกัน — คุณได้ระบบฐานข้อมูลที่ **เร็ว** (แบ่งงานกันทำ), **ทนทาน** (มีสำเนาเผื่อพัง), และ **ขยายต่อได้** (เพิ่ม Shard เมื่อข้อมูลโตขึ้น) ทั้งหมดนี้รันบน Docker — แค่พิมพ์ไม่กี่คำสั่งก็พร้อมใช้งาน!

---

## 🧹 คำสั่ง Cleanup

```bash
# หยุดและลบทุกอย่างรวมถึงข้อมูล
docker compose down -v

# หยุดแต่เก็บข้อมูลไว้ (เริ่มใหม่ทีหลังได้)
docker compose down
```

---

## 📁 โครงสร้างไฟล์ในโปรเจกต์นี้

```
├── docker-compose.yml         # นิยามคลัสเตอร์ทั้งหมด
├── .env.example               # ตัวอย่าง environment variables
├── .gitignore                 # ไม่ track .env และ data dirs
├── prometheus.yml             # ตั้งค่า Prometheus scrape targets
├── mongod/                    # MongoDB node images
│   ├── Dockerfile             # สร้าง mongod image
│   ├── mongod.conf            # ตั้งค่า mongod (auth, replication)
│   └── entrypoint.sh          # สคริปต์เริ่มต้น mongod
├── mongos/                    # MongoDB router images
│   ├── Dockerfile             # สร้าง mongos image
│   └── mongos.conf            # ตั้งค่า mongos
├── coordinator/               # ตัวช่วยตั้งค่าคลัสเตอร์
│   ├── Dockerfile             # สร้าง coordinator image
│   └── init.sh                # สร้าง keyfile + init replicasets + add shards + create users
├── backup/
│   └── entrypoint.sh          # สำรองข้อมูลอัตโนมัติทุกวัน
└── grafana/
    └── dashboard-14997.json   # MongoDB monitoring dashboard
```

---

📝 *เอกสารนี้เขียนสำหรับโปรเจกต์ [mongodb-cluster-shard-docker](https://github.com/Wsangsrichan/mongodb-cluster-shard-docker) — ถ้าสงสัยอะไร เปิด Issue ใน GitHub ได้เลยครับ!*
