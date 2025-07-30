-- Description: Merge any intersecting or adjacent shapes with the same SMP and height

BEGIN;

CREATE TEMP TABLE merged_shapes AS
WITH connected_components AS (
    SELECT
        a.ogr_fid AS id_a,
        b.ogr_fid AS id_b,
        a.smp,
        a.altura
    FROM city_data a
    JOIN city_data b ON 
        a.smp = b.smp AND
        a.altura = b.altura AND
        a.ogr_fid < b.ogr_fid AND
        (ST_Intersects(a.geom, b.geom) OR ST_Touches(a.geom, b.geom))
),
grouped_shapes AS (
    SELECT
        smp,
        altura,
        MIN(id_a) AS group_id,
        ARRAY_AGG(DISTINCT id_a) || ARRAY_AGG(DISTINCT id_b) AS shape_ids
    FROM connected_components
    GROUP BY smp, altura
)
SELECT
    g.group_id,
    g.smp,
    g.altura,
    ARRAY(SELECT DISTINCT u FROM unnest(g.shape_ids) u ORDER BY u) AS shape_ids,
    ST_Buffer(
        ST_Buffer(ST_Union(c.geom), 0.000002), 
        -0.000002
    ) AS merged_geom
FROM grouped_shapes g
JOIN city_data c ON c.ogr_fid = ANY(g.shape_ids)
GROUP BY g.group_id, g.smp, g.altura, g.shape_ids;

UPDATE city_data c
SET geom = m.merged_geom
FROM merged_shapes m
WHERE c.ogr_fid = m.group_id;

DELETE FROM city_data
WHERE ogr_fid IN (
    SELECT u FROM merged_shapes, unnest(shape_ids) AS u
    WHERE u <> group_id
);

DO $$
DECLARE
    merged_count INT;
    group_count INT;
BEGIN
    SELECT COUNT(*) INTO merged_count FROM (
        SELECT unnest(shape_ids) FROM merged_shapes
    ) AS t;
    
    SELECT COUNT(*) INTO group_count FROM merged_shapes;
    
    RAISE NOTICE 'Merged % shapes into % groups', merged_count, group_count;
END $$;

DROP TABLE merged_shapes;

COMMIT;
