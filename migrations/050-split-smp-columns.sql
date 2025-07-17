-- Description: Splits the SMP column into seccion, manzana and parcela for easier handling

BEGIN;

ALTER TABLE city_data
    DROP COLUMN IF EXISTS seccion,
    DROP COLUMN IF EXISTS manzana,
    DROP COLUMN IF EXISTS parcela;

ALTER TABLE city_data
    ADD COLUMN seccion VARCHAR(10),
    ADD COLUMN manzana VARCHAR(10),
    ADD COLUMN parcela VARCHAR(10);

UPDATE city_data
SET seccion = SPLIT_PART(smp, '-', 1),
    manzana = SPLIT_PART(smp, '-', 2),
    parcela = SPLIT_PART(smp, '-', 3);

COMMIT;
