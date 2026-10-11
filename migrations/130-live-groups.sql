-- Description: Link groups (PLAN 4.3-4.4): structures and Live buildings connected through
-- link contacts (120) become one group, classified by shape (1:1, N:1, 1:N, N:M) and, where
-- decidable at this point, its Conflicts reasons. with_parts flags structures a Live
-- building:part mostly lies inside (Live has parts, 4.4). member records each node's group
-- for later migrations.

-- Live has parts: a Live building:part lies mostly inside the structure
DROP TABLE IF EXISTS with_parts;
CREATE TABLE with_parts AS
SELECT DISTINCT s.sid
FROM structure_shapes s
JOIN live_shapes p ON NOT p.is_building AND ST_Intersects(s.geom, p.geom)
WHERE ST_Area(ST_Intersection(s.geom, p.geom)) > 0.5 * p.area;

-- Link groups: structures are nodes sid, Live buildings nodes -lid
DROP TABLE IF EXISTS cc_nodes, cc_edges;
CREATE TEMP TABLE cc_edges AS SELECT sid::BIGINT AS a, -lid::BIGINT AS b FROM contacts WHERE link;
CREATE TEMP TABLE cc_nodes AS
SELECT x AS id, NULL::BIGINT AS comp FROM (SELECT a AS x FROM cc_edges UNION SELECT b FROM cc_edges) n;
ALTER TABLE cc_nodes ADD PRIMARY KEY (id);
SELECT cc_run();

DROP TABLE IF EXISTS live_groups;
CREATE TABLE live_groups AS
SELECT n.comp AS grp,
       COUNT(*) FILTER (WHERE n.id > 0) AS n_st,
       COUNT(*) FILTER (WHERE n.id < 0) AS n_live,
       COUNT(*) FILTER (WHERE n.id < 0 AND l.tagged) AS n_tagged,
       COUNT(DISTINCT s.parcel) AS n_parcels,
       BOOL_OR(w.sid IS NOT NULL) AS has_parts,
       BOOL_OR(NOT s.valid) AS has_invalid,
       BOOL_OR(s.split_by_overlap) AS has_split
FROM cc_nodes n
LEFT JOIN structure_shapes s ON s.sid = n.id
LEFT JOIN live_shapes l ON l.lid = -n.id
LEFT JOIN with_parts w ON w.sid = n.id
GROUP BY n.comp;
ALTER TABLE live_groups ADD PRIMARY KEY (grp);
ALTER TABLE live_groups ADD COLUMN kind TEXT, ADD COLUMN reasons TEXT[], ADD COLUMN held BOOLEAN NOT NULL DEFAULT false;
UPDATE live_groups SET kind = CASE
    WHEN n_st = 1 AND n_live = 1 THEN '1:1'
    WHEN n_live = 1 THEN 'N:1'
    WHEN n_st = 1 THEN '1:N'
    ELSE 'N:M' END;
-- Conflicts subtypes decided per group (4.4), every one that applies; NULL means Reshape
UPDATE live_groups SET reasons = NULLIF(array_remove(ARRAY[
    CASE WHEN has_split THEN 'footprint split by an overlap' END,
    CASE WHEN has_parts THEN 'Live has parts' END,
    CASE WHEN has_invalid THEN 'invalid geometry' END,
    CASE WHEN kind = 'N:M' THEN 'N:M' END,
    CASE WHEN kind = '1:N' AND n_tagged >= 2 THEN '1:N with two or more tagged OSM buildings' END,
    CASE WHEN kind = 'N:1' AND n_tagged = 1 AND n_parcels > 1 THEN 'N:1 tagged OSM building over several parcels' END
    ], NULL), '{}');

DROP TABLE IF EXISTS member;
CREATE TABLE member AS SELECT id, comp AS grp FROM cc_nodes;
ALTER TABLE member ADD PRIMARY KEY (id);
