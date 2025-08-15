-- Description: Run ST_CoverageSimplify on city data to remove redundant vertices

BEGIN;

WITH simplified AS (
  SELECT 
    ogr_fid, 
    ST_CoverageSimplify(geom, 2e-6) OVER (PARTITION BY seccion, manzana) AS simplified_geom
  FROM test
)
UPDATE city_data cd
SET geom = s.simplified_geom
FROM simplified s
WHERE cd.ogr_fid = s.ogr_fid;

COMMIT;
