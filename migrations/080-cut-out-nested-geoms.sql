-- Description: In the case an SMP contains nested geometries,
-- cut out the smaller geoms from the larger ones.
-- Refer to examples/nested-geometries.geojson for an instance of this issue.

WITH contained_union AS (
    SELECT
        container.ogr_fid AS ogr_fid,
        ST_Difference(
            container.geom,
            ST_Union(contained.geom)
        ) AS geom
    FROM city_data container
    INNER JOIN city_data contained
        ON container.smp = contained.smp
        AND container.ogr_fid <> contained.ogr_fid
        AND ST_Contains(container.geom, contained.geom)
    GROUP BY container.ogr_fid, container.geom
)
UPDATE city_data
SET geom = contained_union.geom
FROM contained_union
WHERE city_data.ogr_fid = contained_union.ogr_fid;
