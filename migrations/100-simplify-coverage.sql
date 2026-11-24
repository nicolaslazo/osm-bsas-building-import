-- Description: Simplify each coverage group (088) at ~22 cm, its boundary edges included
-- (PLAN 2.2, 2.8), preserving topology. Ordered by ogr_fid, as in 090, so a run on the same
-- input gives the same result.

WITH simplified AS (
  SELECT
    ogr_fid,
    ST_CoverageSimplify(
      geom,
      2e-6, -- tolerance: ~22 cm
      true  -- simplify boundary edges too
    ) OVER (PARTITION BY ckey ORDER BY ogr_fid) AS simplified_geom
  FROM city_data
)
UPDATE city_data cd
SET geom = s.simplified_geom
FROM simplified s
WHERE cd.ogr_fid = s.ogr_fid;
