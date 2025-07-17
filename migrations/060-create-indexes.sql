-- Description: Create index on the SMP column in the city_data table

CREATE INDEX idx_city_data_smp ON city_data (smp);
CREATE INDEX idx_city_data_seccion ON city_data (seccion);
CREATE INDEX idx_city_data_manzana ON city_data (manzana);
CREATE INDEX idx_city_data_geom ON city_data USING GIST (geom);
