-- Description: Gate 1 (PLAN 5.1). Stops the run unless every block is a valid coverage, no
-- footprint has NULL or EMPTY geometry, and every multipart footprint was cut by 080
-- (nested_geoms container) or split by an overlap in 090 (PLAN 2.6), and the footprint
-- count reconciles at every step of the ledger footprint_counts: each step's count is the
-- count before it, less what it removed, plus what it added. Reports the footprint count.

DO $$
DECLARE
    empties INT;
    invalid_blocks INT;
    multipart INT;
    mismatch TEXT;
BEGIN
    SELECT COUNT(*) INTO empties FROM city_data WHERE geom IS NULL OR ST_IsEmpty(geom);
    IF empties > 0 THEN
        RAISE EXCEPTION 'Gate 1: % footprints with NULL or EMPTY geometry', empties;
    END IF;

    SELECT COUNT(DISTINCT bkey) INTO invalid_blocks FROM (
        SELECT bkey, ST_CoverageInvalidEdges(geom) OVER (PARTITION BY bkey) AS e
        FROM city_data
    ) x WHERE e IS NOT NULL;
    IF invalid_blocks > 0 THEN
        RAISE EXCEPTION 'Gate 1: % blocks are not a valid coverage', invalid_blocks;
    END IF;

    SELECT COUNT(*) INTO multipart FROM city_data c
    WHERE ST_NumGeometries(c.geom) > 1 AND NOT c.split_by_overlap
      AND NOT EXISTS (SELECT 1 FROM nested_geoms n WHERE n.container = c.ogr_fid);
    IF multipart > 0 THEN
        RAISE EXCEPTION 'Gate 1: % multipart footprints neither cut by 080 nor split by an overlap', multipart;
    END IF;

    SELECT format('%s after %s: expected %s, found %s', step, prev_step, prev - removed + added, total)
    INTO mismatch
    FROM (SELECT *, LAG(total) OVER w AS prev, LAG(step) OVER w AS prev_step
          FROM footprint_counts WINDOW w AS (ORDER BY seq)) l
    WHERE total <> prev - removed + added
    ORDER BY seq LIMIT 1;
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'Gate 1: footprint count does not reconcile at %', mismatch;
    END IF;
    SELECT format('%s: expected %s, found %s', step, total, (SELECT COUNT(*) FROM city_data))
    INTO mismatch
    FROM (SELECT step, total FROM footprint_counts ORDER BY seq DESC LIMIT 1) l
    WHERE total <> (SELECT COUNT(*) FROM city_data);
    IF mismatch IS NOT NULL THEN
        RAISE EXCEPTION 'Gate 1: footprint count changed after the last ledger step, %', mismatch;
    END IF;

    RAISE NOTICE 'Gate 1 passed: % footprints in % blocks, reconciled with % source features',
        (SELECT COUNT(*) FROM city_data), (SELECT COUNT(DISTINCT bkey) FROM city_data),
        (SELECT total FROM footprint_counts ORDER BY seq LIMIT 1);
END $$;
