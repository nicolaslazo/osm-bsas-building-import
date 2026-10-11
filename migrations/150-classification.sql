-- Description: One result set per structure (PLAN 4.2): New, Reshape or Conflicts, with
-- every Conflicts reason that applies (4.4), from live_groups (130) and the neighbour rule
-- (140). A structure with any reason is Conflicts. 500 reads this table.

DROP TABLE IF EXISTS classification;
CREATE TABLE classification AS
SELECT sid,
       CASE WHEN reasons IS NOT NULL THEN 'C' WHEN grp IS NOT NULL THEN 'R' ELSE 'N' END AS result,
       reasons, grp, kind
FROM (
    SELECT s.sid, g.grp, g.kind,
           NULLIF(array_remove(CASE
               WHEN g.grp IS NOT NULL THEN
                   g.reasons || CASE WHEN g.held THEN 'overlaps an OSM building that stays' END
               ELSE ARRAY[
                   CASE WHEN s.split_by_overlap THEN 'footprint split by an overlap' END,
                   CASE WHEN w.sid IS NOT NULL THEN 'Live has parts' END,
                   CASE WHEN NOT s.valid THEN 'invalid geometry' END,
                   CASE WHEN EXISTS (SELECT 1 FROM contacts c WHERE c.sid = s.sid)
                        THEN 'overlaps an OSM building without a link' END]
               END, NULL), '{}') AS reasons
    FROM structure_shapes s
    LEFT JOIN member m ON m.id = s.sid
    LEFT JOIN live_groups g ON g.grp = m.grp
    LEFT JOIN with_parts w ON w.sid = s.sid
) r;
ALTER TABLE classification ADD PRIMARY KEY (sid);
