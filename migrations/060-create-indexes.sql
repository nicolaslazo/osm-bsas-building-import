-- Description: Create indexes on the parcel and block keys and the geometry of city_data

-- Later steps (080 cut-outs, 090/100 coverage functions, the merge) return Polygon as well as
-- MultiPolygon, so the column takes any geometry type.
ALTER TABLE city_data ALTER COLUMN geom TYPE geometry(Geometry, 4326);

CREATE INDEX IF NOT EXISTS idx_city_data_smp ON city_data (smp);
CREATE INDEX IF NOT EXISTS idx_city_data_parcel_id ON city_data (parcel_id);
CREATE INDEX IF NOT EXISTS idx_city_data_bkey ON city_data (bkey);
