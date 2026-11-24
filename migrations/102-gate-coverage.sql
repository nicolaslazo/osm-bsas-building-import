-- Description: Gate 1 (PLAN 5.1). Stops the run unless every coverage group (088) is a valid
-- coverage, no two coverage groups come within 2.2 cm of each other (PLAN 2.8), no
-- footprint has NULL or EMPTY geometry, and every multipart footprint was cut by 080
-- (nested_geoms container) or split by an overlap in 090 (PLAN 2.6), and the footprint
-- count reconciles at every step of the ledger footprint_counts: each step's count is the
-- count before it, less what it removed, plus what it added. Reports the footprint count.

DO $$
DECLARE
    empties INT;
    invalid_groups INT;
    close_groups TEXT;
    multipart INT;
    mismatch TEXT;
BEGIN
    SELECT COUNT(*) INTO empties FROM city_data WHERE geom IS NULL OR ST_IsEmpty(geom);
    IF empties > 0 THEN
        RAISE EXCEPTION 'Gate 1: % footprints with NULL or EMPTY geometry', empties;
    END IF;

    SELECT COUNT(DISTINCT ckey) INTO invalid_groups FROM (
        SELECT ckey, ST_CoverageInvalidEdges(geom) OVER (PARTITION BY ckey) AS e
        FROM city_data
    ) x WHERE e IS NOT NULL;
    IF invalid_groups > 0 THEN
        RAISE EXCEPTION 'Gate 1: % coverage groups are not a valid coverage', invalid_groups;
    END IF;

    -- Two coverage groups are cleaned apart, so a wall between them would never be shared.
    -- 088 joins any within 22 cm before cleaning; this catches two that 090 or 100 moved closer
    SELECT string_agg(DISTINCT a.ckey || '/' || b.ckey, ', ') INTO close_groups
    FROM city_data a
    JOIN city_data b ON a.ckey < b.ckey AND ST_DWithin(a.geom, b.geom, 2e-7);
    IF close_groups IS NOT NULL THEN
        RAISE EXCEPTION 'Gate 1: coverage groups within 2.2 cm of each other: %', close_groups;
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

    RAISE NOTICE 'Gate 1 passed: % footprints in % blocks (% coverage groups), reconciled with % source features',
        (SELECT COUNT(*) FROM city_data), (SELECT COUNT(DISTINCT bkey) FROM city_data),
        (SELECT COUNT(DISTINCT ckey) FROM city_data),
        (SELECT total FROM footprint_counts ORDER BY seq LIMIT 1);
END $$;
