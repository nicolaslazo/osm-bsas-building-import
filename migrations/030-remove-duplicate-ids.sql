-- Description: Remove duplicate IDs from city_data table
--
-- It's just ~10 buildings so I don't mind losing them

DELETE FROM city_data
WHERE id IN (
  SELECT id
  FROM city_data
  GROUP BY id
  HAVING COUNT(*) > 1
);
