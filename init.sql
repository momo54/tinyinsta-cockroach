-- init.sql — initialize tables and load small dataset

CREATE TABLE IF NOT EXISTS petitions (
    id INT PRIMARY KEY,
    title STRING NOT NULL
);

CREATE TABLE IF NOT EXISTS signatures (
    id INT PRIMARY KEY,
    petition_id INT NOT NULL REFERENCES petitions(id),
    user_id INT NOT NULL
);

-- Insert small dataset to trigger sharding
INSERT INTO petitions (id, title) VALUES
  (1, 'Ban Plastic Bags'),
  (2, 'Lower Tuition Fees'),
  (3, 'More Trees in Cities');

-- Insert many signatures to go over range split threshold (simulate with small kv.range_bytes)
-- We'll repeat petitions to trigger large number of rows
INSERT INTO signatures (id, petition_id, user_id)
SELECT g, (g % 3) + 1, g
FROM generate_series(1, 6000) AS g;

-- Manual splits to force more ranges
ALTER TABLE signatures SPLIT AT VALUES (1000);
ALTER TABLE signatures SPLIT AT VALUES (2000);
ALTER TABLE signatures SPLIT AT VALUES (3000);
ALTER TABLE signatures SPLIT AT VALUES (4000);
ALTER TABLE signatures SPLIT AT VALUES (5000);

-- Rebalance
ALTER TABLE signatures SCATTER;
