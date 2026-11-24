-- Description: Group blocks that touch into coverage groups (PLAN 2.8). Blocks whose footprints
-- come within 090's snap (~22 cm, 2e-6°) of each other, directly or through a chain, form one
-- group, keyed by its smallest block key (ckey). 090, 100, 101 and Gate 1 partition by it.
-- Runs after 087, on the corrected positions.

DROP TABLE IF EXISTS cc_nodes, cc_edges;
CREATE TEMP TABLE block_ids AS
SELECT bkey, ROW_NUMBER() OVER (ORDER BY bkey)::BIGINT AS id
FROM (SELECT DISTINCT bkey FROM city_data) b;
ALTER TABLE block_ids ADD PRIMARY KEY (id);
CREATE UNIQUE INDEX ON block_ids (bkey);

CREATE TEMP TABLE cc_edges AS
SELECT DISTINCT ia.id AS a, ib.id AS b
FROM city_data a
JOIN city_data b ON a.bkey < b.bkey AND ST_DWithin(a.geom, b.geom, 2e-6)
JOIN block_ids ia ON ia.bkey = a.bkey
JOIN block_ids ib ON ib.bkey = b.bkey;

CREATE TEMP TABLE cc_nodes AS SELECT id, NULL::BIGINT AS comp FROM block_ids;
ALTER TABLE cc_nodes ADD PRIMARY KEY (id);
SELECT cc_run();

-- block_ids numbers blocks in key order, so the component's smallest id is its smallest key
ALTER TABLE city_data DROP COLUMN IF EXISTS ckey;
ALTER TABLE city_data ADD COLUMN ckey VARCHAR(40);
UPDATE city_data c
SET ckey = k.bkey
FROM block_ids b
JOIN cc_nodes n ON n.id = b.id
JOIN block_ids k ON k.id = n.comp
WHERE c.bkey = b.bkey;
CREATE INDEX idx_city_data_ckey ON city_data (ckey);

DO $$
BEGIN
    RAISE NOTICE '088: % block pairs within 22 cm; % blocks in % coverage groups of two or more, largest % blocks (%)',
        (SELECT COUNT(*) FROM cc_edges),
        (SELECT COUNT(*) FROM cc_nodes WHERE comp IN (SELECT comp FROM cc_nodes GROUP BY comp HAVING COUNT(*) > 1)),
        (SELECT COUNT(*) FROM (SELECT comp FROM cc_nodes GROUP BY comp HAVING COUNT(*) > 1) g),
        (SELECT MAX(n) FROM (SELECT COUNT(*) AS n FROM cc_nodes GROUP BY comp) g),
        (SELECT ckey FROM city_data GROUP BY ckey ORDER BY COUNT(DISTINCT bkey) DESC, ckey LIMIT 1);
END $$;

ANALYZE city_data;
