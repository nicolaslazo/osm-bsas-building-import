-- Description: Reshape tasks (PLAN 6.3): Reshape groups whose structures touch form one task,
-- and neighbours of neighbours join it, so one file holds every wall two of them share and
-- ogr2osm gives it one set of nodes. A task never reaches past its block. 500 writes one
-- file per task.

DROP TABLE IF EXISTS cc_nodes, cc_edges;
CREATE TEMP TABLE cc_edges AS
SELECT DISTINCT ka.grp AS a, kb.grp AS b
FROM structures sa
JOIN classification ka ON ka.sid = sa.sid AND ka.result = 'R'
JOIN structures sb ON sb.bkey = sa.bkey AND sb.sid > sa.sid AND sb.geom && sa.geom
JOIN classification kb ON kb.sid = sb.sid AND kb.result = 'R'
WHERE ka.grp <> kb.grp AND ST_Intersects(sa.geom, sb.geom);
CREATE TEMP TABLE cc_nodes AS
SELECT DISTINCT grp AS id, NULL::BIGINT AS comp FROM classification WHERE result = 'R';
ALTER TABLE cc_nodes ADD PRIMARY KEY (id);
SELECT cc_run();

DROP TABLE IF EXISTS reshape_tasks;
CREATE TABLE reshape_tasks AS SELECT id AS grp, comp AS task FROM cc_nodes;
ALTER TABLE reshape_tasks ADD PRIMARY KEY (grp);

DO $$
BEGIN
    RAISE NOTICE '170: % Reshape groups in % tasks, largest % groups',
        (SELECT COUNT(*) FROM reshape_tasks), (SELECT COUNT(DISTINCT task) FROM reshape_tasks),
        (SELECT MAX(n) FROM (SELECT COUNT(*) AS n FROM reshape_tasks GROUP BY task) t);
END $$;
