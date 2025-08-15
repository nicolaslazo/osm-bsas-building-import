-- Description: Remove unnecessary columns from the original dataset

ALTER TABLE city_data 
DROP COLUMN IF EXISTS consolidad,  -- Either 0 or 1. Doesn't look relevant
DROP COLUMN IF EXISTS altos,       -- Only 0s
DROP COLUMN IF EXISTS fuente,      -- Only "Sec Planeamiento"
DROP COLUMN IF EXISTS tipo,        -- Only "Edificio" (building)
DROP COLUMN IF EXISTS origen;      -- Only "Fotogrametría"

-- This is the original ID from the source dataset.
-- Since it might provide some yet undiscovered semantic meaning, we'll keep it for now.
-- DROP COLUMN IF EXISTS id;
