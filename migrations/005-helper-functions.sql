-- Description: Helper functions shared by later migrations.

-- Connected components ("cc") by label propagation. Reads the session's temp tables
-- cc_nodes(id BIGINT PRIMARY KEY, comp BIGINT) and cc_edges(a BIGINT, b BIGINT) and leaves
-- in cc_nodes.comp the smallest id of each node's component.
CREATE OR REPLACE FUNCTION cc_run() RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    iterations INT := 0;
    changed INT;
BEGIN
    UPDATE cc_nodes SET comp = id;
    LOOP
        iterations := iterations + 1;
        WITH e AS (
            SELECT a, b FROM cc_edges UNION ALL SELECT b, a FROM cc_edges
        ), m AS (
            SELECT e.a AS id, MIN(n.comp) AS c
            FROM e JOIN cc_nodes n ON n.id = e.b
            GROUP BY e.a
        )
        UPDATE cc_nodes n SET comp = m.c FROM m WHERE n.id = m.id AND m.c < n.comp;
        GET DIAGNOSTICS changed = ROW_COUNT;
        -- pointer jumping: a node takes its label's label
        UPDATE cc_nodes n SET comp = p.comp FROM cc_nodes p WHERE p.id = n.comp AND p.comp < n.comp;
        EXIT WHEN changed = 0;
    END LOOP;
    RETURN iterations;
END $$;

-- Fill every interior ring whose area is under min_m2 (PLAN 3.5); other rings stay.
CREATE OR REPLACE FUNCTION fill_small_holes(g geometry, min_m2 float8) RETURNS geometry
LANGUAGE sql IMMUTABLE AS $$
    SELECT ST_Collect(ARRAY(
        SELECT ST_MakePolygon(
                   ST_ExteriorRing(p.geom),
                   ARRAY(SELECT ST_InteriorRingN(p.geom, i)
                         FROM generate_series(1, ST_NumInteriorRings(p.geom)) i
                         WHERE ST_Area(ST_MakePolygon(ST_InteriorRingN(p.geom, i))::geography) >= min_m2))
        FROM ST_Dump(g) p
        WHERE ST_GeometryType(p.geom) = 'ST_Polygon'))
$$;

-- Append a row to the footprint count ledger (PLAN 5.1): what a step removed and added, and
-- the footprint count after it. Gate 1 (102) reconciles the rows.
CREATE OR REPLACE FUNCTION log_footprints(step TEXT, removed BIGINT, added BIGINT) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO footprint_counts (step, removed, added, total)
    SELECT step, removed, added, COUNT(*) FROM city_data
$$;
