-- Description: Where a parcel holds nested footprints, cut the nested ones out of the
-- footprint that contains them, so 090's coverage cleaning gets non-overlapping input.
-- Refer to examples/nested-geometries.geojson for an instance of this issue.
--
-- Keyed on parcel_id (PLAN 3.3): Outlier SMP and no-SMP footprints are parcels by
-- themselves and never cut each other. nested_geoms records every cut; 104 uses it to
-- rebuild the base part of each structure (103's outline union restores the holes itself).

DROP TABLE IF EXISTS nested_geoms;

CREATE TABLE nested_geoms AS
SELECT container.ogr_fid AS container, contained.ogr_fid AS contained
FROM city_data container
JOIN city_data contained
    ON container.parcel_id = contained.parcel_id
    AND container.ogr_fid <> contained.ogr_fid
    AND ST_Contains(container.geom, contained.geom);

WITH contained_union AS (
    SELECT n.container AS ogr_fid,
           ST_Difference(c.geom, ST_Union(x.geom)) AS geom
    FROM nested_geoms n
    JOIN city_data c ON c.ogr_fid = n.container
    JOIN city_data x ON x.ogr_fid = n.contained
    GROUP BY n.container, c.geom
)
UPDATE city_data
SET geom = contained_union.geom
FROM contained_union
WHERE city_data.ogr_fid = contained_union.ogr_fid;

DO $$
BEGIN
    RAISE NOTICE '080: % footprints cut around % nested footprints',
        (SELECT COUNT(DISTINCT container) FROM nested_geoms),
        (SELECT COUNT(DISTINCT contained) FROM nested_geoms);
END $$;
