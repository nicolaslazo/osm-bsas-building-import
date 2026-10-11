-- Description: Remove any geoms under 0.5 m2

DO $$
DECLARE n INT;
BEGIN
    DELETE FROM city_data
    WHERE ST_Area(ST_Transform(geom, 22185)) <= 0.5;
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM log_footprints('020', n, 0);
END $$;
