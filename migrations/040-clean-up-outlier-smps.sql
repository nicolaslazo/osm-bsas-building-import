-- Description: Set dummy SMPs for outliers

UPDATE city_data
SET smp = '0-0-0'
WHERE (CHAR_LENGTH(smp) - CHAR_LENGTH(REPLACE(smp, '-', ''))) < 2 or smp IS NULL;
