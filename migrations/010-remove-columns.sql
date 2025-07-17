-- Description: Remove unnecessary columns from the original dataset

ALTER TABLE city_data 
DROP COLUMN IF EXISTS consolidad,
DROP COLUMN IF EXISTS altos,
DROP COLUMN IF EXISTS fuente,
DROP COLUMN IF EXISTS tipo,
DROP COLUMN IF EXISTS origen;
