-- Description: Move the footprints onto the city's 2021 orthophoto (PLAN 2.7), one rigid
-- translation per block: 1.86 m north and 0.41 m west, or the vector offset_blocks gives the
-- block (bin/measure-offset.py). Patch blocks are listed with no movement and stay as
-- delivered. Runs after 085, which gives every footprint its block, and before 090, so
-- coverage cleaning sees the moved positions.

CREATE TEMP TABLE footprint_block AS
SELECT c.ogr_fid, c.block, COALESCE(o.east, -0.41) AS east, COALESCE(o.north, 1.86) AS north, o.block IS NOT NULL AS listed
FROM city_data c
LEFT JOIN offset_blocks o USING (block);

DO $$
DECLARE
    centre GEOMETRY := ST_SetSRID(ST_MakePoint(-58.44, -34.61), 4326);
    lat_m DOUBLE PRECISION := ST_Distance(centre::geography, ST_Translate(centre, 0, 0.01)::geography) / 0.01;
    lon_m DOUBLE PRECISION := ST_Distance(centre::geography, ST_Translate(centre, 0.01, 0)::geography) / 0.01;
    n INT;
BEGIN
    UPDATE city_data c SET geom = ST_Translate(c.geom, b.east / lon_m, b.north / lat_m)
    FROM footprint_block b
    WHERE b.ogr_fid = c.ogr_fid AND (b.east <> 0 OR b.north <> 0);
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE '087: % footprints moved (% by a block''s own vector), % left as delivered; % listed blocks not found',
        n, (SELECT COUNT(*) FROM footprint_block WHERE listed AND (east <> 0 OR north <> 0)),
        (SELECT COUNT(*) FROM footprint_block WHERE east = 0 AND north = 0),
        (SELECT COUNT(*) FROM offset_blocks WHERE block NOT IN (SELECT block FROM footprint_block));
END $$;

ANALYZE city_data;
