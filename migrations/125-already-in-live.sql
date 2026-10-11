-- Description: Structures already in Live (PLAN 5.3), skipped with no change. A structure is
-- already in Live when:
--   a Live building linked to it (120) was last edited by the import account (import_account,
--   from bin/import-datasets.sh): our upload, which nobody has edited since;
--   or a Live building carries its ref:cadastre and the SMP names this structure alone,
--   whatever the shape and wherever it lies, so a mapper's edit after the upload stays;
--   or a Live building linked to it carries its ref:cadastre, where several structures
--   share the SMP.
-- Skipped structures leave structure_shapes and contacts, so 130-160 never see them. Their
-- Live buildings stay in live_shapes, as OSM buildings that stay.

DROP TABLE IF EXISTS already_in_live;
CREATE TABLE already_in_live AS
WITH live AS (
    SELECT ogr_fid AS lid,
           osm_uid IN (SELECT uid FROM import_account) AS ours,
           substring(other_tags FROM '"ref:cadastre"=>"([^"]*)"') AS ref
    FROM live_buildings
    WHERE building IS NOT NULL
), one_structure AS (
    SELECT ref_cadastre FROM structures
    WHERE ref_cadastre IS NOT NULL
    GROUP BY ref_cadastre HAVING COUNT(*) = 1
)
SELECT sid, array_agg(DISTINCT how ORDER BY how) AS how
FROM (
    SELECT c.sid, 'import account' AS how
    FROM contacts c JOIN live l USING (lid)
    WHERE c.link AND l.ours
    UNION ALL
    SELECT s.sid, 'ref:cadastre'
    FROM structures s JOIN one_structure USING (ref_cadastre) JOIN live l ON l.ref = s.ref_cadastre
    UNION ALL
    SELECT c.sid, 'ref:cadastre'
    FROM contacts c JOIN live l USING (lid) JOIN structures s USING (sid)
    WHERE c.link AND l.ref = s.ref_cadastre
) m
GROUP BY sid;
ALTER TABLE already_in_live ADD PRIMARY KEY (sid);

DELETE FROM contacts WHERE sid IN (SELECT sid FROM already_in_live);
DELETE FROM structure_shapes WHERE sid IN (SELECT sid FROM already_in_live);

-- Structures left with a near-identical Live building (IoU at least 0.9). A mapper's edit
-- between the upload and this fetch hides our upload from the import account rule; compare
-- this count with the run before the upload to see how many
DO $$
BEGIN
    RAISE NOTICE '125: % import accounts; % structures already in Live (import account %, ref:cadastre %); % structures left with a Live building of IoU >= 0.9',
        (SELECT COUNT(*) FROM import_account),
        (SELECT COUNT(*) FROM already_in_live),
        (SELECT COUNT(*) FROM already_in_live WHERE 'import account' = ANY (how)),
        (SELECT COUNT(*) FROM already_in_live WHERE 'ref:cadastre' = ANY (how)),
        (SELECT COUNT(DISTINCT sid) FROM contacts
         WHERE link AND overlap / (s_area + l_area - overlap) >= 0.9);
END $$;
