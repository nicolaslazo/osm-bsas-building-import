-- Description: Repair SMP codes and set NULL where no usable SMP exists (PLAN 1.2-1.7).
-- The source spelling is kept in smp_src; smp_reason records why an SMP was dropped.

ALTER TABLE city_data
    ADD COLUMN IF NOT EXISTS smp_src VARCHAR,
    ADD COLUMN IF NOT EXISTS smp_reason VARCHAR;

-- 1.6: double-encoded Ñ (UTF-8 read as Windows-1252), e.g. 37-56-012Ã‘
WITH repaired AS (
    SELECT ogr_fid, smp AS orig, replace(smp, 'Ã‘', 'Ñ') AS fixed FROM city_data
)
UPDATE city_data c
SET smp_src = r.orig,
    -- 1.4: keep the reason, then 1.2: NULL instead of the old dummy 0-0-0
    smp_reason = CASE
        WHEN r.fixed = 'Sin parcelario 2017' THEN r.fixed
        WHEN r.fixed IS NULL THEN 'null'
        -- 1.3: slash-joined SMPs (65-125-021/65-125-022, 60-138-020B/021) name two lots and
        -- the source has no lot geometry to tell which footprint sits on which
        WHEN r.fixed ~ '^[0-9]+-[0-9A-ZÑ]+-[0-9A-ZÑ]+/[0-9A-ZÑ-]+$' THEN 'slash-joined'
        WHEN r.fixed !~ '^[0-9]+-[0-9A-ZÑ]+-[0-9A-ZÑ]+$' THEN 'malformed'
    END,
    smp = CASE
        WHEN r.fixed IS NULL OR r.fixed !~ '^[0-9]+-[0-9A-ZÑ]+-[0-9A-ZÑ]+$' THEN NULL
        ELSE r.fixed
    END
FROM repaired r
WHERE c.ogr_fid = r.ogr_fid;

-- 1.7: 60-026-029A is no longer deleted; its 10 footprints have valid geometry.
