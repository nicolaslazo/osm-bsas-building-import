-- Description: Merge footprints of one parcel and one altura that are connected through
-- shared walls (PLAN 2.5). A shared wall is a line: footprints meeting only at a corner
-- point stay separate. Runs after 100, where shared walls have identical coordinates.
-- Outlier SMP and no-SMP footprints (parcel_id NULL) never merge.

DROP TABLE IF EXISTS cc_nodes, cc_edges;
CREATE TEMP TABLE cc_edges AS
SELECT a.ogr_fid::BIGINT AS a, b.ogr_fid::BIGINT AS b
FROM city_data a
JOIN city_data b
    ON a.parcel_id = b.parcel_id
    AND a.altura IS NOT DISTINCT FROM b.altura
    AND a.ogr_fid < b.ogr_fid
    AND ST_Intersects(a.geom, b.geom)
    AND ST_Relate(a.geom, b.geom, '****1****');

CREATE TEMP TABLE cc_nodes AS
SELECT x AS id, NULL::BIGINT AS comp FROM (SELECT a AS x FROM cc_edges UNION SELECT b FROM cc_edges) n;
ALTER TABLE cc_nodes ADD PRIMARY KEY (id);
SELECT cc_run();

DROP TABLE IF EXISTS merged_geoms;
CREATE TABLE merged_geoms AS
SELECT comp::INT AS kept, id::INT AS merged FROM cc_nodes WHERE id <> comp;

CREATE TEMP TABLE merged_shapes AS
SELECT n.comp::INT AS kept,
       BOOL_OR(ST_NumGeometries(c.geom) > 1) AS had_multipart,
       -- ST_CoverageUnion only drops the shared walls; the other vertices stay exactly
       -- where 100 left them, so walls shared with neighbours still match
       ST_CoverageUnion(c.geom) AS geom,
       MIN(c.bkey) AS bkey
FROM cc_nodes n JOIN city_data c ON c.ogr_fid = n.id
GROUP BY n.comp;

-- Where three or more footprints meet within a few cm, the union can leave an edge that
-- no longer matches its neighbour's (2 blocks on the 2026-09-24 source). Those blocks keep
-- their footprints unmerged, so Gate 1's coverage check still holds. They still join
-- one structure in 103.
CREATE TEMP TABLE unmerged_blocks AS
SELECT DISTINCT bkey FROM (
    SELECT bkey, ST_CoverageInvalidEdges(geom) OVER (PARTITION BY bkey) AS e
    FROM (
        SELECT bkey, geom FROM city_data c
        WHERE c.bkey IN (SELECT bkey FROM merged_shapes)
          AND NOT EXISTS (SELECT 1 FROM cc_nodes n WHERE n.id = c.ogr_fid)
        UNION ALL
        SELECT bkey, geom FROM merged_shapes
    ) candidate
) x WHERE e IS NOT NULL;

DELETE FROM merged_geoms WHERE kept IN (SELECT kept FROM merged_shapes WHERE bkey IN (SELECT bkey FROM unmerged_blocks));
DELETE FROM merged_shapes WHERE bkey IN (SELECT bkey FROM unmerged_blocks);

DO $$
BEGIN
    RAISE NOTICE '101: % blocks left unmerged: %',
        (SELECT COUNT(*) FROM unmerged_blocks), (SELECT string_agg(bkey, ', ') FROM unmerged_blocks);
END $$;

UPDATE city_data c SET geom = m.geom FROM merged_shapes m WHERE c.ogr_fid = m.kept;
-- A merged footprint is split by an overlap (090) when any footprint in it was
UPDATE city_data c SET split_by_overlap = true
FROM merged_geoms m JOIN city_data d ON d.ogr_fid = m.merged
WHERE c.ogr_fid = m.kept AND d.split_by_overlap;
DELETE FROM city_data WHERE ogr_fid IN (SELECT merged FROM merged_geoms);
SELECT log_footprints('101', (SELECT COUNT(*) FROM merged_geoms), 0);

-- nested_geoms (080) follows the merge; a pair merged into one footprint is gone
UPDATE nested_geoms n SET container = m.kept FROM merged_geoms m WHERE n.container = m.merged;
UPDATE nested_geoms n SET contained = m.kept FROM merged_geoms m WHERE n.contained = m.merged;
DELETE FROM nested_geoms WHERE container = contained;

DO $$
DECLARE bad INT;
BEGIN
    SELECT COUNT(*) INTO bad FROM merged_shapes WHERE ST_NumGeometries(geom) > 1 AND NOT had_multipart;
    IF bad > 0 THEN
        RAISE EXCEPTION '101: % merged footprints are multipart', bad;
    END IF;
    RAISE NOTICE '101: merged % footprints into % (% multipart footprints remain, % of them split by an overlap in 090)',
        (SELECT COUNT(*) FROM merged_geoms) + (SELECT COUNT(*) FROM merged_shapes),
        (SELECT COUNT(*) FROM merged_shapes),
        (SELECT COUNT(*) FROM city_data WHERE ST_NumGeometries(geom) > 1),
        (SELECT COUNT(*) FROM city_data WHERE ST_NumGeometries(geom) > 1 AND split_by_overlap);
END $$;
