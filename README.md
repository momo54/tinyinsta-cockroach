# 🐓 CockroachDB Sharding Demo — Petition Use Case

This repository demonstrates how to set up a 5-node [CockroachDB](https://www.cockroachlabs.com/) cluster using Docker Compose, with a small dataset (petitions and signatures) to explore **auto-sharding** and **distributed queries**.

## 📆 Setup

### ✅ Requirements
- GitHub Codespace or Docker installed locally
- Internet access

### 🐳 Launch the cluster

```bash
docker compose down -v    # Reset volumes if needed
docker compose up -d      # Start the CockroachDB cluster
```

Then, **you must manually initialize the cluster**:

```bash
docker exec -it cockroach-cockroach1-1 ./cockroach init --insecure --host=cockroach1
```

Once done, open the admin UI at:  
- http://localhost:8080 (node 1)  
- http://localhost:8081 (node 2)  
- http://localhost:8082 (node 3)  
- http://localhost:8083 (node 4)  
- http://localhost:8084 (node 5)  

### 🧲 Initialize the schema and load data

```bash
docker exec -it cockroach-cockroach1-1 ./cockroach sql --insecure --host=cockroach1 -f /init.sql
```

### 🖊️ Connect to SQL shell

```bash
docker exec -it cockroach-cockroach1-1 ./cockroach sql --insecure
```

### 🌐 Puis-je exécuter du SQL dans l'interface Web ?

Courte réponse: non pour le cluster local. L'interface web sur le port 8080 (DB Console) sert au monitoring et à l'observabilité (nœuds, requêtes, ranges, etc.) mais n'intègre pas d'éditeur SQL interactif en mode self‑hosted. Un éditeur SQL dans le navigateur est disponible sur CockroachDB Cloud, pas dans cette démo Docker.

Utilisez l'une des options suivantes pour taper des requêtes SQL:

- CLI depuis le conteneur (recommandé ici):
  ```bash
  docker exec -it cockroach-cockroach1-1 ./cockroach sql --insecure --host=cockroach1
  ```

- Depuis votre machine avec psql (protocole PostgreSQL):
  ```bash
  psql "postgresql://root@localhost:26257/defaultdb?sslmode=disable"
  ```
  Paramètres: host=localhost, port=26257, user=root, database=defaultdb, sslmode=disable (cluster en mode --insecure).

- Client SQL graphique (DBeaver, TablePlus, DataGrip, etc.):
  - Driver: PostgreSQL
  - Host: localhost
  - Port: 26257
  - User: root
  - Database: defaultdb
  - SSL: désactivé (insecure)

## 📄 Useful SQL Commands

### 👀 Show databases and tables

```sql
SHOW DATABASES;
USE defaultdb;
SHOW TABLES;
```

### 🦢🥝 Petition dataset — top petitions

```sql
SELECT p.title, COUNT(s.id) AS nb_signatures
FROM petitions p
LEFT JOIN signatures s ON p.id = s.petition_id
GROUP BY p.id
ORDER BY nb_signatures DESC;
```

### 🔧 Show sharding info (ranges)

```sql
SHOW RANGES FROM TABLE signatures;
```

```sql
SELECT
  range_id,
  lease_holder,
  start_key,
  end_key
FROM
  [SHOW RANGES FROM TABLE signatures];
```

### 🧬 Compute key hash for shard mapping

```sql
SELECT encode(crdb_internal.mvcc_computed_pk(signatures.*), 'hex'), *
FROM signatures
LIMIT 10;
```

### ⚖️ Force manual sharding for demonstration

```sql
-- Force range splits for fine-grained shards
ALTER TABLE signatures SPLIT AT VALUES (1000);
ALTER TABLE signatures SPLIT AT VALUES (2000);
ALTER TABLE signatures SPLIT AT VALUES (3000);
ALTER TABLE signatures SPLIT AT VALUES (4000);
ALTER TABLE signatures SPLIT AT VALUES (5000);

-- Rebalance the split ranges across nodes
ALTER TABLE signatures SCATTER;
```

---

## 📁 Files

- `docker-compose.yml`: Sets up the cluster and loads data
- `init.sql`: Creates schema, inserts data, and triggers range splits
- `README.md`: You're reading it!

## 🧠 Learning Goals

- Understand CockroachDB sharding model (ranges)
- Observe automatic and manual range splits
- Practice JOINs on a distributed DB
- Learn basic distributed SQL introspection

---

© 2025 – Educational TP for M1 students – Université de Nantes

## 📸 Tiny Instagram dataset (optional)

If you prefer a social-graph use case, use `init_instagram.sql` to create a tiny Instagram-like schema:

- Tables: `users`, `posts`, `follows`, `likes`
- Indexes for common queries (feeds, followers, likes)
- Manual splits/scatter on `posts` and `likes` to visualize sharding

### Load the dataset

```bash
docker exec -it cockroach-cockroach1-1 ./cockroach sql --insecure --host=cockroach1 -f /init_instagram.sql
```

### Try some queries

```sql
-- Show ranges for posts
SHOW RANGES FROM TABLE insta.posts;

-- Where is a specific post stored?
SHOW RANGE FROM TABLE insta.posts FOR ROW (2100);

-- Feed for user 1 (people they follow)
SELECT * FROM insta.feed_for_user;

-- Top liked posts
SELECT p.id, p.author_id, pl.likes
FROM insta.post_likes pl
JOIN insta.posts p ON p.id = pl.post_id
ORDER BY pl.likes DESC
LIMIT 10;
```
