-- Remove repeated points from the geometry

UPDATE city_data SET geom = ST_RemoveRepeatedPoints(geom);
