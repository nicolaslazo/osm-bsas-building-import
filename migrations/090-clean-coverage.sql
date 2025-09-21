-- Description: Clean coverage with aggressive node snapping and gap removal

BEGIN;

WITH clean AS (
  SELECT
    ogr_fid,
    ST_CoverageClean(
      geom,
      0.0000002,       -- snapping distance: ~20cm
      0.0000002,       -- gap cleaning: ~20cm
      'MERGE_MAX_AREA' -- merge strategy
    ) OVER (PARTITION BY seccion, manzana) AS clean_geom
  FROM city_data
)
UPDATE city_data cd
SET geom = s.clean_geom
FROM clean s
WHERE cd.ogr_fid = s.ogr_fid;

COMMIT;
