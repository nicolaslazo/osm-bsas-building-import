-- Remove repeated points from the geometry. ST_CoverageClean (090) also removes them, but
-- 080's ST_Contains and ST_Difference run before it.

UPDATE city_data SET geom = ST_RemoveRepeatedPoints(geom);
