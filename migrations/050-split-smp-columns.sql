-- Description: Split the SMP into seccion, manzana and parcela with normalized keys (PLAN 1.1).
--
-- seccion loses its leading zeros and manzana the zeros of its numeric prefix
-- (020-014 and 20-014 are one block). parcela keeps the source spelling.

ALTER TABLE city_data
    DROP COLUMN IF EXISTS seccion,
    DROP COLUMN IF EXISTS manzana,
    DROP COLUMN IF EXISTS parcela,
    DROP COLUMN IF EXISTS pkey,
    DROP COLUMN IF EXISTS asentamiento_informal,
    DROP COLUMN IF EXISTS bkey;

ALTER TABLE city_data
    ADD COLUMN seccion VARCHAR(10),
    ADD COLUMN manzana VARCHAR(10),
    ADD COLUMN parcela VARCHAR(20),
    ADD COLUMN pkey VARCHAR(40),
    ADD COLUMN asentamiento_informal BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN bkey VARCHAR(40);

UPDATE city_data
SET (seccion, manzana, parcela, pkey, bkey, asentamiento_informal) = (
    SELECT s, m, p, s || '-' || m || '-' || p, s || '-' || m, p ~ '^BEM'
    FROM (SELECT COALESCE(NULLIF(LTRIM(SPLIT_PART(smp, '-', 1), '0'), ''), '0') AS s,
                 REGEXP_REPLACE(SPLIT_PART(smp, '-', 2), '^0+([0-9])', '\1') AS m,
                 SUBSTRING(smp FROM '^[^-]+-[^-]+-(.*)$') AS p) parts
)
WHERE smp IS NOT NULL;
