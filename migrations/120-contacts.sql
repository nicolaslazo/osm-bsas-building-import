-- Description: Contacts between structures and Live buildings (PLAN 4.5): any overlap
-- (interiors meet in an area, not a shared wall or corner), with the overlap area in m²
-- and whether it clears the link threshold (4.3: at least 1 m² and over half the smaller
-- shape). Reads live_shapes and structure_shapes (110).

DROP TABLE IF EXISTS contacts;
CREATE TABLE contacts AS
SELECT sid, lid, overlap, s_area, l_area,
       overlap >= 1 AND overlap > 0.5 * LEAST(s_area, l_area) AS link
FROM (
    SELECT s.sid, l.lid, ST_Area(ST_Intersection(s.geom, l.geom)) AS overlap,
           s.area AS s_area, l.area AS l_area
    FROM structure_shapes s
    JOIN live_shapes l ON l.is_building AND ST_Intersects(s.geom, l.geom)
    WHERE ST_Relate(s.geom, l.geom, '2********')
) t
WHERE overlap > 0;
CREATE INDEX ON contacts (sid);
CREATE INDEX ON contacts (lid);
