-- Description: Snap all vertices to a grid to fix excentricities

UPDATE city_data
SET geom = ST_SnapToGrid(geom, 0.0000005);
