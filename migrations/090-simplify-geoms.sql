-- Description: Run ST_CoverageSimplify on city data to remove redundant vertices

BEGIN;

WITH simplified AS (
  SELECT 
    ogr_fid, 
    ST_CoverageSimplify(geom, 0.000002) OVER (PARTITION BY seccion, manzana) AS simplified_geom
  FROM city_data
)
UPDATE city_data cd
SET geom = s.simplified_geom
FROM simplified s
WHERE cd.ogr_fid = s.ogr_fid;

COMMIT;
