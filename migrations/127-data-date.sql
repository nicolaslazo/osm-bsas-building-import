-- Description: Rules on the data date (PLAN 4.9, 4.10), the cutoff in data_date
-- (bin/import-datasets.sh). late_live lists the Live buildings whose way or relation was not
-- tagged building=* at the cutoff (live_at_cutoff): mapped after it, redrawn as a new way, or
-- tagged later. works_structures lists the structures on a parcel where a building work of
-- any type started on or after the cutoff (building_works, Obras Iniciadas). 130 and 150 turn
-- both into Conflicts reasons.

DROP TABLE IF EXISTS late_live;
CREATE TABLE late_live AS
SELECT l.ogr_fid AS lid
FROM live_buildings l
WHERE l.building IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM live_at_cutoff c
      WHERE c.type = CASE WHEN l.osm_id IS NOT NULL THEN 'relation' ELSE 'way' END
        AND c.id = COALESCE(l.osm_id, l.osm_way_id)::BIGINT);
ALTER TABLE late_live ADD PRIMARY KEY (lid);

-- The works' SMP spelled as structures.pkey (1.1): no leading zeros in seccion or in the
-- manzana's number, parcela upper-cased
DROP TABLE IF EXISTS works_structures;
CREATE TABLE works_structures AS
SELECT DISTINCT s.sid
FROM building_works w
JOIN structures s ON s.pkey =
    ltrim(trim(w.seccion), '0') || '-' ||
    regexp_replace(upper(trim(w.manzana)), '^0*([0-9]+)', '\1') || '-' ||
    upper(trim(w.parcela))
JOIN structure_shapes USING (sid)
WHERE w.fecha_inicio_obra ~ '^\d{4}-\d{2}-\d{2}$'
  AND w.fecha_inicio_obra::DATE >= (SELECT cutoff FROM data_date);
ALTER TABLE works_structures ADD PRIMARY KEY (sid);

DO $$
BEGIN
    IF (SELECT cutoff FROM data_date) IS NULL THEN
        RAISE EXCEPTION '127: no data date';
    END IF;
    RAISE NOTICE '127: cutoff %; % Live buildings mapped after it; % structures on a parcel with a building work since',
        (SELECT cutoff FROM data_date),
        (SELECT COUNT(*) FROM late_live),
        (SELECT COUNT(*) FROM works_structures);
END $$;
