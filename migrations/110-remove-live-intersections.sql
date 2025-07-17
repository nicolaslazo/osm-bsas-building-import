-- Description: Creates a materialized view containing SMPs from city_data
-- that don't intersect with any geometries in live_buildings table

BEGIN;

DROP MATERIALIZED VIEW IF EXISTS non_intersecting;

CREATE MATERIALIZED VIEW non_intersecting AS
WITH intersecting_smps AS (
    SELECT DISTINCT cd_inner.smp
    FROM live_buildings lb
    JOIN city_data cd_inner ON ST_Intersects(cd_inner.geom, lb.geom)
)
SELECT cd.*
FROM city_data cd
WHERE cd.smp NOT IN (SELECT smp FROM intersecting_smps);

CREATE INDEX idx_non_intersecting_geom ON non_intersecting USING GIST (geom);

COMMENT ON MATERIALIZED VIEW non_intersecting IS 'SMPs from city_data that do not intersect with any live OpenStreetMap buildings';

COMMIT;
