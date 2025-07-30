-- Description: Find overlapping geometries in the same seccion/manzana but different SMPs
-- Cut out overlapping areas from the SMP with higher alphabetical value

BEGIN;

WITH geom_overlaps AS (
    SELECT 
        a.ogr_fid,
        b.ogr_fid AS b_id,
        -- We'll always preserve the lower ogr_fid geometry
        a.geom,
        -- Convert result to MultiPolygon to match the column type
        CASE
            WHEN ST_IsEmpty(ST_Difference(b.geom, a.geom)) THEN NULL
            ELSE ST_Multi(ST_CollectionExtract(ST_Difference(b.geom, a.geom), 3))
        END as b_geom_cut
    FROM city_data a
    JOIN city_data b ON 
        a.seccion = b.seccion AND
        a.manzana = b.manzana AND
        a.smp <> b.smp AND
        a.ogr_fid < b.ogr_fid AND
        ST_Intersects(a.geom, b.geom) AND
        NOT ST_Touches(a.geom, b.geom)
)
UPDATE city_data cd
SET geom = go.b_geom_cut
FROM geom_overlaps go
WHERE cd.ogr_fid = go.b_id
AND go.b_geom_cut IS NOT NULL;

COMMIT;
