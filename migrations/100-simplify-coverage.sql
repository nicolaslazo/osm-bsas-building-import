-- Description: Apply aggressive line simplification while preserving topology

BEGIN;

WITH simplified AS (
  SELECT
    ogr_fid,
    ST_CoverageSimplify(
      geom,
      0.000005, -- tolerance: ~50cm simplification
      true      -- simplify boundary edges too
    ) OVER (PARTITION BY seccion, manzana) AS simplified_geom
  FROM city_data
)
UPDATE city_data cd
SET geom = s.simplified_geom
FROM simplified s
WHERE cd.ogr_fid = s.ogr_fid;

COMMIT;
