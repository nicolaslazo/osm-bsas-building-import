-- Description: Build comparison shapes for classifying structures against Live (PLAN 4.1):
-- live_shapes (Live buildings and parts) and structure_shapes (structure outlines), both
-- rounded to the 7-digit output grid (3.2) so later overlap tests agree exactly.

-- Live buildings and parts
DROP TABLE IF EXISTS live_shapes CASCADE;
CREATE TABLE live_shapes AS
SELECT lid, is_building, tagged, geom, ST_Area(geom) AS area
FROM (
    SELECT ogr_fid AS lid,
           building IS NOT NULL AS is_building,
           -- tags beyond building=yes: another building value or any other key
           (building IS DISTINCT FROM 'yes'
            OR COALESCE(name, aeroway, amenity, admin_level, barrier, boundary, craft, geological,
                        historic, land_area, landuse, leisure, man_made, military, "natural", office,
                        place, shop, sport, tourism, "building:part") IS NOT NULL
            OR NULLIF(other_tags, '') IS NOT NULL) AS tagged,
           ST_Transform(ST_MakeValid(ST_SnapToGrid(geom, 1e-7)), 5347) AS geom
    FROM live_buildings
) t;
ALTER TABLE live_shapes ADD PRIMARY KEY (lid);
CREATE INDEX idx_live_shapes_geom ON live_shapes USING GIST (geom);

-- Structure outlines on the same grid
DROP TABLE IF EXISTS structure_shapes;
CREATE TABLE structure_shapes AS
SELECT sid, parcel, valid, split_by_overlap, geom, ST_Area(geom) AS area
FROM (
    SELECT sid,
           COALESCE(parcel_id, 'fp-' || sid) AS parcel,
           ST_IsValid(geom) AS valid,
           split_by_overlap,
           ST_Transform(ST_MakeValid(ST_SnapToGrid(geom, 1e-7)), 5347) AS geom
    FROM structures
) t;
ALTER TABLE structure_shapes ADD PRIMARY KEY (sid);
CREATE INDEX idx_structure_shapes_geom ON structure_shapes USING GIST (geom);
