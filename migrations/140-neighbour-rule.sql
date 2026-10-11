-- Description: Neighbour rule (PLAN 4.3): holds a group when it overlaps a Live building
-- outside the group that stays — unlinked, already in Conflicts, or itself held — repeated
-- until stable. A held Reshape group goes to Conflicts; a group already in Conflicts is
-- held too, so the reason is recorded with its others. outside_contacts pairs each group
-- with the groups of Live buildings its structures touch outside it.

-- Contacts of a group's structures with Live buildings outside the group, and the group
-- of that Live building (NULL when it is linked to nothing)
CREATE TEMP TABLE outside_contacts AS
SELECT DISTINCT ms.grp, ml.grp AS live_grp
FROM contacts c
JOIN member ms ON ms.id = c.sid
LEFT JOIN member ml ON ml.id = -c.lid
WHERE ml.grp IS DISTINCT FROM ms.grp;
CREATE INDEX ON outside_contacts (grp);
ANALYZE member, outside_contacts, live_groups;

DO $$
DECLARE n INT; iterations INT := 0;
BEGIN
    LOOP
        iterations := iterations + 1;
        UPDATE live_groups g SET held = true
        WHERE NOT g.held AND EXISTS (
            SELECT 1
            FROM outside_contacts o
            LEFT JOIN live_groups lg ON lg.grp = o.live_grp
            WHERE o.grp = g.grp
              AND (o.live_grp IS NULL OR lg.reasons IS NOT NULL OR lg.held));
        GET DIAGNOSTICS n = ROW_COUNT;
        EXIT WHEN n = 0;
    END LOOP;
    RAISE NOTICE '140: neighbour rule settled after % iterations', iterations;
END $$;
