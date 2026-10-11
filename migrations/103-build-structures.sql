-- Description: Build structures (PLAN 3.3): the footprints of one parcel connected through
-- shared walls, directly or through a chain, whatever their altura. A nested footprint
-- shares the wall of its hole, so it joins the structure around it. Outlier SMP and no-SMP
-- footprints (parcel_id NULL) are structures of one footprint (PLAN 4.2).
--
-- structures.geom is the outline: the union of the structure's footprints, which also
-- restores the holes 080 cut, then fills every hole under 1 sq m (PLAN 3.5); larger holes
-- stay and are published as multipolygon relations. height is the highest altura in the
-- structure. split_by_overlap is set when any footprint in it was split by an overlap in 090
-- (PLAN 2.6). ref_cadastre is the SMP in its source spelling (PLAN 3.4), the most common one
-- where a parcel's footprints spell it differently; NULL for no-SMP footprints and
-- asentamientos informales.

DROP TABLE IF EXISTS cc_nodes, cc_edges;
CREATE TEMP TABLE cc_edges AS
SELECT a.ogr_fid::BIGINT AS a, b.ogr_fid::BIGINT AS b
FROM city_data a
JOIN city_data b
    ON a.parcel_id = b.parcel_id
    AND a.ogr_fid < b.ogr_fid
    AND ST_Intersects(a.geom, b.geom)
    AND ST_Relate(a.geom, b.geom, '****1****');

CREATE TEMP TABLE cc_nodes AS
SELECT ogr_fid::BIGINT AS id, ogr_fid::BIGINT AS comp FROM city_data;
ALTER TABLE cc_nodes ADD PRIMARY KEY (id);
SELECT cc_run();

ALTER TABLE city_data DROP COLUMN IF EXISTS sid;
ALTER TABLE city_data ADD COLUMN sid INT;
UPDATE city_data c SET sid = n.comp FROM cc_nodes n WHERE n.id = c.ogr_fid;
CREATE INDEX idx_city_data_sid ON city_data (sid);

DROP TABLE IF EXISTS structures_raw;
CREATE TEMP TABLE structures_raw AS
SELECT sid,
       MIN(parcel_id) AS parcel_id,
       MIN(pkey) AS pkey,
       MIN(bkey) AS bkey,
       MIN(seccion) AS seccion,
       BOOL_OR(outlier) AS outlier,
       BOOL_OR(asentamiento_informal) AS asentamiento_informal,
       COUNT(*) AS n_fp,
       MAX(altura) AS height,
       BOOL_OR(split_by_overlap) AS split_by_overlap,
       CASE WHEN NOT BOOL_OR(asentamiento_informal) THEN MODE() WITHIN GROUP (ORDER BY smp) END AS ref_cadastre,
       ST_UnaryUnion(ST_Collect(geom)) AS geom
FROM city_data
GROUP BY sid;

-- Fill every outline hole under 1 sq m (PLAN 3.5); larger holes stay and are published as
-- multipolygon relations. Holes that held a nested footprint are already filled by the union.
ALTER TABLE structures_raw ADD COLUMN has_small_hole BOOLEAN;
UPDATE structures_raw
SET has_small_hole = EXISTS (
    SELECT 1 FROM ST_Dump(geom) p, generate_series(1, ST_NumInteriorRings(p.geom)) i
    WHERE ST_Area(ST_MakePolygon(ST_InteriorRingN(p.geom, i))::geography) < 1.0
);

DROP TABLE IF EXISTS structures CASCADE;
CREATE TABLE structures AS
SELECT sid, parcel_id, pkey, bkey, seccion, outlier, asentamiento_informal, n_fp, height,
       split_by_overlap, ref_cadastre,
       CASE WHEN has_small_hole THEN fill_small_holes(geom, 1.0) ELSE geom END AS geom
FROM structures_raw;
ALTER TABLE structures ADD PRIMARY KEY (sid);
CREATE INDEX idx_structures_geom ON structures USING GIST (geom);

DO $$
BEGIN
    RAISE NOTICE '103: % footprints form % structures (% of one footprint, % multipart outlines)',
        (SELECT COUNT(*) FROM city_data),
        (SELECT COUNT(*) FROM structures),
        (SELECT COUNT(*) FROM structures WHERE n_fp = 1),
        (SELECT COUNT(*) FROM structures WHERE ST_NumGeometries(geom) > 1);
    RAISE NOTICE '103: filled small holes in % outlines; % outlines keep holes',
        (SELECT COUNT(*) FROM structures_raw WHERE has_small_hole),
        (SELECT COUNT(*) FROM structures WHERE EXISTS (
            SELECT 1 FROM ST_Dump(geom) p WHERE ST_NumInteriorRings(p.geom) > 0));
END $$;
