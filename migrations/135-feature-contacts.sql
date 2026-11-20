-- Description: Feature contacts (PLAN 4.7): structures that overlap an OSM feature other than
-- a building (live_features, loaded by bin/import-datasets.sh). A feature overlaps when it
-- intersects the structure shrunk by 0.5 m, so a way that only touches a wall does not count.
-- Every class and every layer counts. feature_contacts holds one row per such structure, with
-- the features it overlaps as osm_type/osm_id. The reason goes on the structure's link group
-- here, so 140 treats the group as staying; 150 adds it to structures in no group.

DROP TABLE IF EXISTS feature_shapes;
CREATE TEMP TABLE feature_shapes AS
SELECT osm_type || '/' || osm_id AS feature,
       ST_Transform(CASE WHEN is_area THEN ST_MakeValid(geom) ELSE geom END, 5347) AS geom
FROM live_features;
CREATE INDEX ON feature_shapes USING GIST (geom);
ANALYZE feature_shapes;

DROP TABLE IF EXISTS feature_contacts;
CREATE TABLE feature_contacts AS
SELECT s.sid, array_agg(f.feature ORDER BY f.feature) AS features
FROM structure_shapes s
JOIN feature_shapes f ON ST_Intersects(s.geom, f.geom)
WHERE ST_Intersects(ST_Buffer(s.geom, -0.5), f.geom)
GROUP BY s.sid;
ALTER TABLE feature_contacts ADD PRIMARY KEY (sid);

UPDATE live_groups g
SET reasons = COALESCE(g.reasons, '{}') || 'overlaps an OSM feature other than a building'::TEXT
WHERE g.grp IN (SELECT m.grp FROM feature_contacts fc JOIN member m ON m.id = fc.sid);
