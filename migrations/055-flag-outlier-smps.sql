-- Description: Flag Outlier SMP footprints and set the parcel key (PLAN 1.5).
--
-- parcel_id is the key footprints group by (merge 2.5, structures 3.3); it is NULL for
-- footprints that are parcels by themselves: no SMP (1.2) and every Outlier SMP (1.5).

ALTER TABLE city_data
    DROP COLUMN IF EXISTS outlier,
    DROP COLUMN IF EXISTS parcel_id;

ALTER TABLE city_data
    ADD COLUMN outlier BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN parcel_id VARCHAR(40);

-- Outlier SMP: parcela is anything but an ordinary number with an optional letter suffix
-- (015, 006A, 01LL, 012Ñ; all-zero is not ordinary), or the parcel holds more than 50 footprints.
UPDATE city_data
SET outlier = true
WHERE smp IS NOT NULL
  AND (parcela !~ '^[0-9]+([A-ZÑ]|LL)?$'
       OR parcela ~ '^0+$'
       OR pkey IN (SELECT pkey FROM city_data WHERE pkey IS NOT NULL GROUP BY pkey HAVING COUNT(*) > 50));

UPDATE city_data SET parcel_id = pkey WHERE smp IS NOT NULL AND NOT outlier;

DO $$
DECLARE r RECORD;
BEGIN
    SELECT COUNT(*) FILTER (WHERE smp IS NULL) AS no_smp,
           COUNT(*) FILTER (WHERE outlier) AS outl,
           COUNT(DISTINCT pkey) FILTER (WHERE outlier) AS outl_parcels,
           COUNT(DISTINCT parcel_id) AS parcels
    INTO r FROM city_data;
    RAISE NOTICE '055: % no-SMP footprints, % Outlier SMP footprints in % parcels, % ordinary parcels',
        r.no_smp, r.outl, r.outl_parcels, r.parcels;
END $$;
