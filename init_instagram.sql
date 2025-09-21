-- init_instagram.sql — Tiny Instagram demo (users, posts, follows, likes)
-- Compatible with CockroachDB v23.x, self-hosted demo in --insecure mode

-- Safety: create database/schema if needed
CREATE DATABASE IF NOT EXISTS insta;
SET DATABASE = insta;

-- Users
CREATE TABLE IF NOT EXISTS users (
  id           INT PRIMARY KEY,
  username     STRING UNIQUE NOT NULL,
  full_name    STRING,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- Posts authored by users
CREATE TABLE IF NOT EXISTS posts (
  id           INT PRIMARY KEY,
  author_id    INT NOT NULL REFERENCES users(id),
  caption      STRING,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- Follow relationships: follower -> followee
-- Composite PK prevents duplicates and supports lookups by follower or followee
CREATE TABLE IF NOT EXISTS follows (
  follower_id  INT NOT NULL REFERENCES users(id),
  followee_id  INT NOT NULL REFERENCES users(id),
  created_at   TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id)
);

-- Likes: who liked which post
CREATE TABLE IF NOT EXISTS likes (
  user_id      INT NOT NULL REFERENCES users(id),
  post_id      INT NOT NULL REFERENCES posts(id),
  created_at   TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (user_id, post_id)
);

-- Useful secondary indexes for common access patterns
-- 1) Post feed for a user (their own posts): posts by author, newest first
CREATE INDEX IF NOT EXISTS posts_author_created_idx ON posts (author_id, created_at DESC);

-- 2) Who a user follows (outgoing)
CREATE INDEX IF NOT EXISTS follows_by_follower_idx ON follows (follower_id);

-- 3) Who follows a user (incoming)
CREATE INDEX IF NOT EXISTS follows_by_followee_idx ON follows (followee_id);

-- 4) Likes by post (to count/scroll likers)
CREATE INDEX IF NOT EXISTS likes_by_post_idx ON likes (post_id, created_at DESC);

-- 5) Likes by user (user activity)
CREATE INDEX IF NOT EXISTS likes_by_user_idx ON likes (user_id, created_at DESC);

-- Seed small dataset
INSERT INTO users (id, username, full_name) VALUES
  (1, 'alice', 'Alice A.'),
  (2, 'bob', 'Bob B.'),
  (3, 'carol', 'Carol C.'),
  (4, 'dave', 'Dave D.'),
  (5, 'eve', 'Eve E.')
ON CONFLICT (id) DO NOTHING;

-- Each user posts 10 posts to create enough rows for splitting
INSERT INTO posts (id, author_id, caption, created_at)
SELECT p_id, author,
       'Post #' || p_id::STRING || ' by user ' || author::STRING AS caption,
       now() - (p_id % 50) * INTERVAL '1 minute'
FROM (
  SELECT author, generate_series(1,10) AS seq FROM (VALUES (1),(2),(3),(4),(5)) AS u(author)
) AS g
JOIN LATERAL (
  SELECT (author*1000 + seq) AS p_id
) AS ids ON true
ON CONFLICT (id) DO NOTHING;

-- Follow graph (some cross following)
INSERT INTO follows (follower_id, followee_id) VALUES
  (1,2),(1,3),(2,1),(2,3),(3,1),(3,2),
  (4,1),(4,2),(5,1),(5,3)
ON CONFLICT DO NOTHING;

-- Likes: each user likes posts from others
INSERT INTO likes (user_id, post_id, created_at)
SELECT u.id, p.id, now() - (p.id % 120) * INTERVAL '1 second'
FROM users u
JOIN posts p ON p.author_id <> u.id AND (p.id % (u.id+2)) = 0
ON CONFLICT DO NOTHING;

-- Force manual splits (sharding) on posts and likes by primary key to visualize ranges
-- Adjust split points to your generated IDs (posts use 1001..5010)
ALTER TABLE posts  SPLIT AT VALUES (2000);
ALTER TABLE posts  SPLIT AT VALUES (3000);
ALTER TABLE posts  SPLIT AT VALUES (4000);
ALTER TABLE posts  SPLIT AT VALUES (5000);
ALTER TABLE posts  SCATTER;

-- likes PK is (user_id, post_id) → splitting only on the first column helps create multiple ranges
ALTER INDEX likes@primary SPLIT AT VALUES (2), (3), (4), (5);
ALTER INDEX likes@primary SCATTER;

-- Helpful views/queries for the demo
-- User feed = posts by people I follow, newest first
CREATE OR REPLACE VIEW feed_for_user AS
SELECT p.*
FROM posts p
JOIN follows f ON f.followee_id = p.author_id
WHERE f.follower_id = 1
ORDER BY p.created_at DESC
LIMIT 50;

-- Count likes per post
CREATE OR REPLACE VIEW post_likes AS
SELECT post_id, COUNT(*) AS likes
FROM likes
GROUP BY post_id;

-- Sample introspection queries (leave as comments for copy/paste)
-- SHOW RANGES FROM TABLE posts;
-- SELECT range_id, crdb_internal.pretty_key(start_key, 2) AS start_span,
--        crdb_internal.pretty_key(end_key, 2)   AS end_span,
--        lease_holder, voting_replicas
-- FROM [SHOW RANGES FROM INDEX posts@primary];

-- Example: which range stores post id 2100?
-- SHOW RANGE FROM TABLE posts FOR ROW (2100);

-- Example: EXPLAIN a feed lookup for user 1
-- EXPLAIN SELECT p.id, p.author_id, p.caption
-- FROM posts p
-- JOIN follows f ON f.followee_id = p.author_id
-- WHERE f.follower_id = 1
-- ORDER BY p.created_at DESC
-- LIMIT 20;
