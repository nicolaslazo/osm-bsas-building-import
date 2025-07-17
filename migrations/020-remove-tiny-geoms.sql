-- Description: Remove any geoms under 0.5 m2

DELETE FROM city_data
WHERE ST_Area(ST_Transform(geom, 22185)) <= 0.5;
