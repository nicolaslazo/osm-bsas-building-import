-- Description: Give no-SMP footprints a block key (PLAN 4.6), so 090 and 100 clean them
-- together with the footprints beside them.
--
-- No-SMP footprints connected through gaps of at most 22 cm (090's snap, 2e-6°) form a
-- group. A group with any footprint within 22 cm of a real block's footprint joins that
-- block whole; a group that reaches no block is a block by itself. A group that reaches
-- two blocks stops the run.

CREATE TEMP TABLE nosmp_groups AS
SELECT ogr_fid, ST_ClusterDBSCAN(geom, eps := 2e-6, minpoints := 1) OVER () AS grp
FROM city_data
WHERE smp IS NULL;

CREATE TEMP TABLE nosmp_reach AS
SELECT g.grp, c.bkey
FROM nosmp_groups g
JOIN city_data n ON n.ogr_fid = g.ogr_fid
JOIN city_data c ON c.smp IS NOT NULL AND ST_DWithin(n.geom, c.geom, 2e-6)
GROUP BY g.grp, c.bkey;

DO $$
DECLARE n INT;
BEGIN
    SELECT COUNT(*) INTO n FROM (SELECT grp FROM nosmp_reach GROUP BY grp HAVING COUNT(*) > 1) x;
    IF n > 0 THEN
        RAISE EXCEPTION '085: % no-SMP groups reach two or more blocks', n;
    END IF;
END $$;

UPDATE city_data c
SET bkey = COALESCE(r.bkey, 'nosmp-' || g.grp)
FROM nosmp_groups g
LEFT JOIN nosmp_reach r USING (grp)
WHERE c.ogr_fid = g.ogr_fid;

DO $$
BEGIN
    RAISE NOTICE '085: % no-SMP groups, % join a block (% footprints), % blocks in all',
        (SELECT COUNT(DISTINCT grp) FROM nosmp_groups),
        (SELECT COUNT(*) FROM nosmp_reach),
        (SELECT COUNT(*) FROM nosmp_groups WHERE grp IN (SELECT grp FROM nosmp_reach)),
        (SELECT COUNT(DISTINCT bkey) FROM city_data);
END $$;

ANALYZE city_data;
