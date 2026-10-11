-- Description: Build building parts (PLAN 3.3): one part per footprint of every structure of
-- two or more footprints, with the footprint's altura. A footprint 080 cut around nested
-- footprints gets its base part, the union with them, which restores the holes and notches of
-- the cut; where the structure is only that footprint and its nested ones, the base part has
-- the outline's shape. Every part hole under 1 sq m is filled, as in the outline (PLAN 3.5).
-- A structure of one footprint has no parts.

CREATE TEMP TABLE nested AS
SELECT n.container AS ogr_fid, ST_Collect(x.geom) AS geom
FROM nested_geoms n JOIN city_data x ON x.ogr_fid = n.contained
GROUP BY n.container;
ALTER TABLE nested ADD PRIMARY KEY (ogr_fid);

DROP TABLE IF EXISTS parts;
CREATE TABLE parts AS
SELECT c.sid, c.ogr_fid, c.altura,
       n.ogr_fid IS NOT NULL AS base,
       CASE WHEN n.ogr_fid IS NULL THEN c.geom ELSE ST_UnaryUnion(ST_Collect(c.geom, n.geom)) END AS geom
FROM city_data c
JOIN structures s ON s.sid = c.sid AND s.n_fp > 1
LEFT JOIN nested n ON n.ogr_fid = c.ogr_fid;

UPDATE parts SET geom = fill_small_holes(geom, 1.0)
WHERE EXISTS (
    SELECT 1 FROM ST_Dump(geom) p, generate_series(1, ST_NumInteriorRings(p.geom)) i
    WHERE ST_Area(ST_MakePolygon(ST_InteriorRingN(p.geom, i))::geography) < 1.0
);
ALTER TABLE parts ADD PRIMARY KEY (ogr_fid);
CREATE INDEX idx_parts_sid ON parts (sid);

-- The parts fill the outline (PLAN 3.3); reported, not a gate
CREATE TEMP TABLE unfilled AS
SELECT s.sid, ST_Area(ST_SymDifference(s.geom, ST_UnaryUnion(ST_Collect(p.geom)))::geography) AS m2
FROM structures s JOIN parts p USING (sid)
GROUP BY s.sid, s.geom;

DO $$
BEGIN
    RAISE NOTICE '104: % parts in % structures, % base parts, % multipart parts',
        (SELECT COUNT(*) FROM parts),
        (SELECT COUNT(DISTINCT sid) FROM parts),
        (SELECT COUNT(*) FROM parts WHERE base),
        (SELECT COUNT(*) FROM parts WHERE ST_NumGeometries(geom) > 1);
    RAISE NOTICE '104: % structures whose parts differ from the outline by over 0.01 sq m (% sq m in all)',
        (SELECT COUNT(*) FROM unfilled WHERE m2 > 0.01),
        (SELECT round(SUM(m2)::numeric, 1) FROM unfilled WHERE m2 > 0.01);
END $$;
