SHELL := /bin/bash

DC := docker compose
COCK := docker exec -i cockroach-cockroach1-1 ./cockroach
HOST := --insecure --host=cockroach1
N ?= 2
SVC := cockroach$(N)

.PHONY: up down init sql load-petitions load-insta ranges-posts range-post rowcounts \
	show-nodes ranges-posts-pretty lease-post watch-lease-post watch-ranges-posts \
	stop-node start-node fast-failover show-failover scatter-posts

up:
	$(DC) up -d

down:
	$(DC) down -v

init:
	# Initialize the cluster (only once after up)
	docker exec -it cockroach-cockroach1-1 ./cockroach init --insecure --host=cockroach1 || true

sql:
	# Open interactive SQL shell
	docker exec -it cockroach-cockroach1-1 ./cockroach sql --insecure

load-petitions:
	# Load petition/signatures dataset
	$(COCK) sql $(HOST) < init.sql

load-insta:
	# Load tiny Instagram dataset
	$(COCK) sql $(HOST) < init_instagram.sql

ranges-posts:
	# Show ranges for insta.posts
	echo "SHOW RANGES FROM TABLE insta.posts;" | $(COCK) sql $(HOST)

range-post:
	# Show range for a specific post id; use make range-post ID=2100
	echo "SHOW RANGE FROM TABLE insta.posts FOR ROW ($${ID:-2100});" | $(COCK) sql $(HOST)

rowcounts:
	# Quick counts for insta dataset
	echo "SELECT 'users', count(*) FROM insta.users; \nSELECT 'posts', count(*) FROM insta.posts; \nSELECT 'follows', count(*) FROM insta.follows; \nSELECT 'likes', count(*) FROM insta.likes;" | $(COCK) sql $(HOST)

# --- Failover / leases observation helpers ---

show-nodes:
	# Show node liveness and basics (v23.x compatible)
	echo "SELECT s.node_id, s.address, s.locality, l.membership, l.draining, l.decommissioning, l.updated_at FROM crdb_internal.kv_node_status AS s LEFT JOIN crdb_internal.gossip_liveness AS l USING (node_id) ORDER BY s.node_id;" | $(COCK) sql $(HOST)

ranges-posts-pretty:
	# Pretty-print ranges for insta.posts with lease holder and replicas
	echo "SELECT range_id, start_key AS start_span, end_key AS end_span, lease_holder, voting_replicas FROM [SHOW RANGES FROM INDEX insta.posts@primary];" | $(COCK) sql $(HOST)

lease-post:
	# Lease info for a specific post id; use make lease-post ID=2100
	echo "SHOW RANGE FROM TABLE insta.posts FOR ROW ($${ID:-2100});" | $(COCK) sql $(HOST)

watch-lease-post:
	# Continuously observe lease holder for a given post id (Ctrl+C to stop); make watch-lease-post ID=2100
	bash -c "while true; do echo '--- ' \`date\` ' ---'; echo 'SHOW RANGE FROM TABLE insta.posts FOR ROW ('\"$${ID:-2100}\"');' | $(COCK) sql $(HOST); sleep 2; done"

watch-ranges-posts:
	# Continuously observe all post ranges (Ctrl+C to stop)
	bash -c "while true; do echo '--- ' \`date\` ' ---'; echo \"SELECT range_id, start_key AS start_span, end_key AS end_span, lease_holder, voting_replicas FROM [SHOW RANGES FROM INDEX insta.posts@primary];\" | $(COCK) sql $(HOST); sleep 3; done"

stop-node:
	# Stop one Cockroach node container (default N=2) — e.g., make stop-node N=3
	$(DC) stop $(SVC)

start-node:
	# Start one Cockroach node container (default N=2) — e.g., make start-node N=3
	$(DC) start $(SVC)

fast-failover:
	# Speed up re-replication on dead nodes (optional)
	echo "SET CLUSTER SETTING server.time_until_store_dead = '30s';" | $(COCK) sql $(HOST)

show-failover:
	# Check current failover/dead-store timeout setting
	echo "SHOW CLUSTER SETTING server.time_until_store_dead;" | $(COCK) sql $(HOST)

scatter-posts:
	# Re-scatter posts ranges to rebalance after node restarts (best-effort)
	echo "ALTER TABLE insta.posts SCATTER;" | $(COCK) sql $(HOST)
