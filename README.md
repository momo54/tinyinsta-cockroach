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
# Option 1 (recommended): stream the SQL into the container via stdin
docker exec -i cockroach-cockroach1-1 ./cockroach sql --insecure --host=cockroach1 < init_instagram.sql

# Option 2: if the file is mounted at /init_instagram.sql inside the container
# (e.g., add a volume mapping in docker-compose), then:
# docker exec -it cockroach-cockroach1-1 ./cockroach sql --insecure --host=cockroach1 -f /init_instagram.sql
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

### Explain plans to study distribution

```sql
-- 1) Lookup a single post by PK (span pruning to one key)
EXPLAIN SELECT * FROM insta.posts WHERE id = 2100;

-- 2) Feed for user 1 (posts by people they follow)
EXPLAIN SELECT p.id, p.author_id, p.caption
FROM insta.posts p
JOIN insta.follows f ON f.followee_id = p.author_id
WHERE f.follower_id = 1
ORDER BY p.created_at DESC
LIMIT 20;

-- 3) Count likes for a post (uses likes_by_post_idx)
EXPLAIN SELECT COUNT(*) FROM insta.likes WHERE post_id = 2100;

-- 4) Which range holds post 2100?
SHOW RANGE FROM TABLE insta.posts FOR ROW (2100);

-- 5) Make key bounds human-readable for posts
SELECT range_id,
  start_key AS start_span,
  end_key   AS end_span,
  lease_holder, voting_replicas
FROM [SHOW RANGES FROM INDEX insta.posts@primary];
```

Reading tips:
- spans: [/2100 - /2100] indicates exact PK lookup (no full scan).
- lookup join: for each left row, an index lookup on the right table—optimal when join keys are indexed.
- distribution: local vs full—full means operators run on multiple nodes.

### Expected observations

- PK lookup on `insta.posts` with `WHERE id = 2100`:
  - `table: insta.posts@primary`, `spans: [/2100 - /2100]` (span pruning to a single key)
  - `distribution: local` is common for single-key lookups

- Feed for user 1 (join posts × follows):
  - Plan includes a `lookup join` using `follows(follower_id)` and `posts(author_id, created_at)` index
  - Limited scan on `follows` for `follower_id = 1`, then lookups on `posts`
  - With LIMIT + ORDER BY, expect a `limit` and ordered scan on `posts_author_created_idx`

- Likes count for a given post:
  - Uses `likes_by_post_idx`; spans limited to the given `post_id`
  - For `EXPLAIN ANALYZE`, check `rows read from KV` stays proportional to the number of likes on that post

- Sharding view:
  - `SHOW RANGES FROM TABLE insta.posts` should reflect manual splits at 2000/3000/4000/5000
  - `SHOW RANGE FROM TABLE insta.posts FOR ROW (2100)` should map to the [2000,3000) range

  ## 🛠 Makefile shortcuts (optional)

  You can use the provided Makefile to speed up common tasks:

  ```bash
  make up            # Start the cluster
  make init          # Initialize the cluster (once)
  make sql           # Open interactive SQL shell
  make load-petitions
  make load-insta
  make ranges-posts  # SHOW RANGES FROM TABLE insta.posts
  make range-post ID=2100  # SHOW RANGE FOR ROW
  make rowcounts     # Quick counts for insta tables
  ```

## 🔄 Démonstration: failover et déplacement de leases

Montrez le comportement du cluster quand un nœud s'arrête puis redémarre: les leases (droit de lecture/écriture pour un range) basculent automatiquement et, si un nœud reste indisponible suffisamment longtemps, les réplicas sont re-répliqués ailleurs.

Pré-requis: chargez le dataset Instagram pour visualiser des ranges sur `insta.posts`.

### 1) Avant l'arrêt — observez l'état

```bash
make show-nodes
make ranges-posts-pretty
make lease-post ID=2100   # Voir le lease holder pour la clé 2100
```

Astuce: lancez en continu pour observer les changements en direct:

```bash
make watch-lease-post ID=2100
# ou
make watch-ranges-posts
```

### 2) Arrêtez un nœud et observez la bascule

Dans un autre terminal:

```bash
make stop-node N=3   # arrête le conteneur cockroach3
```

Retournez sur le watcher: au bout de quelques secondes, le `lease_holder` de la range ciblée doit changer (vers un autre nœud présent dans `voting_replicas`).

Vous pouvez aussi revérifier ponctuellement:

```bash
make show-nodes
make lease-post ID=2100
make ranges-posts-pretty
```

### 3) Accélérer la détection de nœud mort (optionnel)

Par défaut, CockroachDB attend plusieurs minutes avant de considérer un store « dead » et de lancer une re-rélication. Pour la démo, vous pouvez réduire ce délai:

```bash
make fast-failover
make show-failover
```

Laissez le nœud arrêté > 30s, puis observez si `voting_replicas` change (un nouveau réplica peut apparaître). Note: le recluster/SCATTER n'est pas instantané et peut continuer en arrière-plan.

### 4) Redémarrez le nœud

```bash
make start-node N=3
```

Ensuite, vous pouvez re-scatter les ranges pour rééquilibrer:

```bash
make scatter-posts
make ranges-posts-pretty
```

Notes utiles:
- `lease_holder` peut migrer dynamiquement selon la charge et la latence, même sans panne.
- Les `voting_replicas` représentent l'ensemble des réplicas votants pour un range. Ils ne changent qu'en cas de reconfiguration (ajout/retrait de réplicas), ce qui prend plus de temps que le simple transfert de lease.
- Pour cartographier les IDs de nœud avec les conteneurs/adresses, utilisez `SHOW NODES;`.
