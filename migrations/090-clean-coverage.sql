-- Description: Clean each block's coverage (PLAN 2.1, 2.3, 4.6): snap nodes within ~22 cm,
-- fill gaps narrower than ~2.2 cm, merge overlaps into the larger footprint.
-- Footprints the cleaning collapses to NULL or EMPTY are dropped.
-- Footprints the cleaning splits into more parts are recorded in split_footprints (PLAN 2.6):
-- a footprint that also splits when cleaned alone splits at a neck of its own, and each piece
-- becomes a footprint; any other split comes from an overlap, and the footprint stays whole
-- and is flagged split_by_overlap, which sends its structure to Conflicts (150).

-- The result depends on the order of a block's footprints: ordered by ogr_fid, a run on the
-- same input gives the same result
CREATE TEMP TABLE clean AS
  SELECT
    ogr_fid,
    ST_CoverageClean(
      geom,
      2e-7,            -- gap maximum width: ~2.2 cm
      2e-6,            -- snapping distance: ~22 cm
      'MERGE_MAX_AREA' -- merge strategy
    ) OVER (PARTITION BY bkey ORDER BY ogr_fid) AS clean_geom
  FROM city_data;

-- Footprints the cleaning collapses, kept with their geometry before cleaning for review
DROP TABLE IF EXISTS cleaned_away;
CREATE TABLE cleaned_away AS
SELECT c.* FROM city_data c JOIN clean s USING (ogr_fid)
WHERE s.clean_geom IS NULL OR ST_IsEmpty(s.clean_geom);

-- The same cleaning on each split footprint alone, without its neighbours
DROP TABLE IF EXISTS split_footprints;
CREATE TABLE split_footprints AS
SELECT ogr_fid, block_parts, ST_NumGeometries(self_geom) AS self_parts,
       CASE WHEN ST_NumGeometries(self_geom) >= block_parts THEN 'neck' ELSE 'overlap' END AS cause
FROM (
    SELECT c.ogr_fid,
           ST_NumGeometries(s.clean_geom) AS block_parts,
           ST_CoverageClean(c.geom, 2e-7, 2e-6, 'MERGE_MAX_AREA') OVER (PARTITION BY c.ogr_fid) AS self_geom
    FROM city_data c JOIN clean s USING (ogr_fid)
    WHERE ST_NumGeometries(s.clean_geom) > ST_NumGeometries(c.geom)
) x;
ALTER TABLE split_footprints ADD PRIMARY KEY (ogr_fid);

UPDATE city_data cd
SET geom = s.clean_geom
FROM clean s
WHERE cd.ogr_fid = s.ogr_fid;

ALTER TABLE city_data DROP COLUMN IF EXISTS split_by_overlap;
ALTER TABLE city_data ADD COLUMN split_by_overlap BOOLEAN NOT NULL DEFAULT false;
UPDATE city_data SET split_by_overlap = true
WHERE ogr_fid IN (SELECT ogr_fid FROM split_footprints WHERE cause = 'overlap');

-- Neck splits: the largest piece keeps the footprint's ogr_fid, every other piece becomes a
-- new footprint with the same attributes
CREATE TEMP TABLE neck_pieces AS
SELECT ogr_fid, geom, rank,
       CASE WHEN rank = 1 THEN ogr_fid
            ELSE (SELECT MAX(ogr_fid) FROM city_data)
                 + ROW_NUMBER() OVER (PARTITION BY rank = 1 ORDER BY ogr_fid, rank) END AS piece_fid
FROM (
    SELECT c.ogr_fid, d.geom,
           ROW_NUMBER() OVER (PARTITION BY c.ogr_fid ORDER BY ST_Area(d.geom) DESC, d.path) AS rank
    FROM city_data c
    JOIN split_footprints f ON f.ogr_fid = c.ogr_fid AND f.cause = 'neck'
    CROSS JOIN LATERAL ST_Dump(c.geom) d
) x;

ALTER TABLE split_footprints ADD COLUMN piece_fids INT[];
UPDATE split_footprints f SET piece_fids = p.fids
FROM (SELECT ogr_fid, array_agg(piece_fid ORDER BY rank) AS fids FROM neck_pieces GROUP BY ogr_fid) p
WHERE f.ogr_fid = p.ogr_fid;

CREATE TEMP TABLE neck_rows AS
SELECT p.piece_fid, p.geom AS piece_geom, c.*
FROM neck_pieces p JOIN city_data c ON c.ogr_fid = p.ogr_fid
WHERE p.rank > 1;
UPDATE neck_rows SET ogr_fid = piece_fid, geom = piece_geom;
ALTER TABLE neck_rows DROP COLUMN piece_fid, DROP COLUMN piece_geom;

UPDATE city_data c SET geom = p.geom
FROM neck_pieces p WHERE p.ogr_fid = c.ogr_fid AND p.rank = 1;
INSERT INTO city_data SELECT * FROM neck_rows;
SELECT log_footprints('090 neck splits', 0, (SELECT COUNT(*) FROM neck_rows));

-- nested_geoms (080) follows the neck pieces: a nested footprint belongs to the piece of its
-- container nearest to it, and every piece of a nested footprint stays nested
UPDATE nested_geoms n
SET container = (
    SELECT p.piece_fid FROM neck_pieces p JOIN city_data x ON x.ogr_fid = n.contained
    WHERE p.ogr_fid = n.container ORDER BY ST_Distance(p.geom, x.geom), p.rank LIMIT 1)
WHERE n.container IN (SELECT ogr_fid FROM split_footprints WHERE cause = 'neck')
  AND EXISTS (SELECT 1 FROM city_data x WHERE x.ogr_fid = n.contained);
INSERT INTO nested_geoms (container, contained)
SELECT n.container, p.piece_fid
FROM nested_geoms n JOIN neck_pieces p ON p.ogr_fid = n.contained AND p.rank > 1;

DO $$
BEGIN
    RAISE NOTICE '090: % footprints split at a neck into % footprints; % split by an overlap stay whole',
        (SELECT COUNT(*) FROM split_footprints WHERE cause = 'neck'),
        (SELECT COUNT(*) FROM neck_pieces),
        (SELECT COUNT(*) FROM split_footprints WHERE cause = 'overlap');
END $$;

DO $$
DECLARE n INT;
BEGIN
    DELETE FROM city_data WHERE geom IS NULL OR ST_IsEmpty(geom);
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE '090: dropped % footprints with NULL or EMPTY geometry', n;
    PERFORM log_footprints('090 NULL or EMPTY', (SELECT COUNT(*) FROM cleaned_away), 0);
END $$;
