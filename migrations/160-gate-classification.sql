-- Description: Gate 2 (PLAN 5.1). Stops the run unless classification covers every
-- structure not already in Live (125) and no New structure overlaps a Live building. Reports
-- the N/R/C counts, the structures already in Live and the number of Reshape Live buildings
-- (in a group neither Conflicts nor held).

DO $$
DECLARE bad INT;
BEGIN
    IF (SELECT COUNT(*) FROM classification) + (SELECT COUNT(*) FROM already_in_live)
       <> (SELECT COUNT(*) FROM structures) THEN
        RAISE EXCEPTION 'Gate 2: classification and structures not already in Live differ in count';
    END IF;
    SELECT COUNT(*) INTO bad FROM classification k JOIN contacts c USING (sid) WHERE k.result = 'N';
    IF bad > 0 THEN
        RAISE EXCEPTION 'Gate 2: % New structures overlap a Live building', bad;
    END IF;
    RAISE NOTICE 'Gate 2 passed. Structures: N %, R %, C %, already in Live %. Reshape Live buildings: %',
        (SELECT COUNT(*) FROM classification WHERE result = 'N'),
        (SELECT COUNT(*) FROM classification WHERE result = 'R'),
        (SELECT COUNT(*) FROM classification WHERE result = 'C'),
        (SELECT COUNT(*) FROM already_in_live),
        (SELECT COUNT(*) FROM member ml JOIN live_groups g USING (grp)
         WHERE ml.id < 0 AND g.reasons IS NULL AND NOT g.held);
END $$;
