CREATE DATABASE IF NOT EXISTS ENERGYDB2;
USE ENERGYDB2;

-- Country table
CREATE TABLE country_3 (
    CID VARCHAR(10) PRIMARY KEY,
    Country VARCHAR(100) UNIQUE
);

-- Emission table
CREATE TABLE emission_3 (
    country VARCHAR(100),
    energy_type VARCHAR(50),
    year INT,
    emission DOUBLE,
    per_capita_emission DOUBLE,
    FOREIGN KEY (country) REFERENCES country_3(Country)
);

-- Population table
CREATE TABLE population_3 (
    countries VARCHAR(100),
    year INT,
    Value DOUBLE,
    FOREIGN KEY (countries) REFERENCES country_3(Country)
);

-- Production table
CREATE TABLE production_3 (
    country VARCHAR(100),
    energy VARCHAR(50),
    year INT,
    production DOUBLE,
    FOREIGN KEY (country) REFERENCES country_3(Country)
);

-- GDP table
CREATE TABLE gdp_3 (
    Country VARCHAR(100),
    year INT,
    Value DOUBLE,
    FOREIGN KEY (Country) REFERENCES country_3(Country)
);

-- Consumption table
CREATE TABLE consum_3 (
    country VARCHAR(100),
    energy VARCHAR(50),
    year INT,
    consumption DOUBLE,
    FOREIGN KEY (country) REFERENCES country_3(Country)
);

SELECT COUNT(*) FROM country_3;
SELECT COUNT(*) FROM population_3;
SELECT COUNT(*) FROM production_3;
SELECT COUNT(*) FROM consum_3;
SELECT COUNT(*) FROM emission_3;
SELECT COUNT(*) FROM gdp_3;

SELECT * FROM country_3 LIMIT 5;
SELECT * FROM population_3 LIMIT 5;
SELECT * FROM production_3 LIMIT 5;
SELECT * FROM consum_3 LIMIT 5;
SELECT * FROM gdp_3 LIMIT 5;
SELECT * FROM emission_3 LIMIT 5;


ALTER TABLE population_3
ADD CONSTRAINT fk_population_country
FOREIGN KEY (countries) REFERENCES country_3(Country);

ALTER TABLE production_3
ADD CONSTRAINT fk_production_country
FOREIGN KEY (country) REFERENCES country_3(Country);

ALTER TABLE consum_3
ADD CONSTRAINT fk_consum_country
FOREIGN KEY (country) REFERENCES country_3(Country);

ALTER TABLE emission_3
ADD CONSTRAINT fk_emission_country
FOREIGN KEY (country) REFERENCES country_3(Country);

ALTER TABLE gdp_3
ADD CONSTRAINT fk_gdp_country
FOREIGN KEY (Country) REFERENCES country_3(Country);

-- create a view that normalizes each child table to the canonical country name
CREATE OR REPLACE VIEW v_emission AS
SELECT e.*, TRIM(e.country) AS country_name
FROM emission_3 e;

CREATE OR REPLACE VIEW v_population AS
SELECT p.*, TRIM(p.countries) AS country_name
FROM population_3 p;

CREATE OR REPLACE VIEW v_production AS
SELECT pr.*, TRIM(pr.country) AS country_name
FROM production_3 pr;

CREATE OR REPLACE VIEW v_consumption AS
SELECT co.*, TRIM(co.country) AS country_name
FROM consum_3 co;

CREATE OR REPLACE VIEW v_gdp AS
SELECT g.*, TRIM(g.Country) AS country_name
FROM gdp_3 g;

/*ANALYSIS
--1.What is the total emission per country for the most recent year available?
SELECT c.CID, c.Country,
       SUM(e.emission) AS total_emission
FROM emission_3 e
JOIN country_3 c ON TRIM(e.country) = TRIM(c.Country)
WHERE e.year = (SELECT MAX(year) FROM emission_3)
GROUP BY c.CID, c.Country
ORDER BY total_emission DESC;

--2.What are the top 5 countries by GDP in the most recent year?
SELECT c.CID, g.Country, g.Value AS gdp
FROM gdp_3 g
JOIN country_3 c ON TRIM(g.Country) = TRIM(c.Country)
WHERE g.year = (SELECT MAX(year) FROM gdp_3)
ORDER BY g.Value DESC
LIMIT 5;

--3.Compare energy production and consumption by country and year. 
SELECT t.country, t.year,
       IFNULL(p.total_production, 0) AS total_production,
       IFNULL(c.total_consumption, 0) AS total_consumption
FROM (
   SELECT country, year FROM production_3
   UNION
   SELECT country, year FROM consum_3
) t
LEFT JOIN (
   SELECT country, year, SUM(production) AS total_production
   FROM production_3
   GROUP BY country, year
) p ON t.country = p.country AND t.year = p.year
LEFT JOIN (
   SELECT country, year, SUM(consumption) AS total_consumption
   FROM consum_3
   GROUP BY country, year
) c ON t.country = c.country AND t.year = c.year
ORDER BY t.country, t.year;

--4.Which energy types contribute most to emissions across all countries?
SELECT energy_type, SUM(emission) AS total_emission
FROM emission_3
GROUP BY energy_type
ORDER BY total_emission DESC;

-------------Trend Analysis Over Time-------------
--.How have global emissions changed year over year?

WITH yearly AS (
  SELECT year, SUM(emission) AS total_emission
  FROM v_emission
  GROUP BY year
)
SELECT
  year,
  total_emission,
  ROUND((total_emission - LAG(total_emission) OVER (ORDER BY year))
        / NULLIF(LAG(total_emission) OVER (ORDER BY year),0) * 100, 2) AS pct_change_vs_prev_year
FROM yearly
ORDER BY year;

--2.What is the trend in GDP for each country over the given years?
---Year-by-year GDP for each country:
SELECT TRIM(Country) AS country, year, SUM(Value) AS gdp_value
FROM v_gdp
GROUP BY TRIM(Country), year
ORDER BY country, year;

---Compound Annual Growth Rate (CAGR) for each country across available span:


3.How has population growth affected total emissions in each country?

WITH emissions_by_year AS (
  SELECT TRIM(country_name) AS country, year, SUM(emission) AS total_emission
  FROM v_emission
  GROUP BY TRIM(country_name), year
),
population_by_year AS (
  SELECT TRIM(countries) AS country, year, SUM(Value) AS population
  FROM v_population
  GROUP BY TRIM(countries), year
),
joined AS (
  SELECT e.country, e.year, e.total_emission, p.population
  FROM emissions_by_year e
  JOIN population_by_year p ON e.country = p.country AND e.year = p.year
)
SELECT country,
  (COUNT(*)*SUM(total_emission*population) - SUM(total_emission)*SUM(population)) /
  ( SQRT( (COUNT(*)*SUM(total_emission*total_emission) - SUM(total_emission)*SUM(total_emission))
        * (COUNT(*)*SUM(population*population) - SUM(population)*SUM(population)) ) ) AS pearson_corr
FROM joined
GROUP BY country
ORDER BY pearson_corr DESC;

--4.Has energy consumption increased or decreased over the years for major economies?
-- choose top 5 GDP countries in the most recent GDP year
WITH latest_gdp_year AS (
  SELECT MAX(year) AS y FROM v_gdp
),
top_gdp AS (
  SELECT TRIM(Country) AS country
  FROM v_gdp
  WHERE year = (SELECT y FROM latest_gdp_year)
  ORDER BY Value DESC
  LIMIT 5
)
SELECT TRIM(co.country) AS country, co.year, SUM(co.consumption) AS total_consumption
FROM v_consumption co
JOIN top_gdp t ON TRIM(co.country) = t.country
GROUP BY TRIM(co.country), co.year
ORDER BY country, year;

---5.What is the average yearly change in emissions per capita for each country?
WITH pc AS (
  SELECT TRIM(country_name) AS country, year, AVG(per_capita_emission) AS pc_emission
  FROM v_emission
  GROUP BY TRIM(country_name), year
),
diffs AS (
  SELECT country, year, pc_emission,
         pc_emission - LAG(pc_emission) OVER (PARTITION BY country ORDER BY year) AS yoy_change
  FROM pc
)
SELECT country,
       ROUND(AVG(yoy_change), 6) AS avg_yearly_change_in_pc_emission
FROM diffs
WHERE yoy_change IS NOT NULL
GROUP BY country
ORDER BY avg_yearly_change_in_pc_emission DESC;

--------------Ratio & Per Capita Analysis----------
.What is the emission-to-GDP ratio for each country by year?
WITH emis AS (
  SELECT TRIM(country_name) AS country, year, SUM(emission) AS total_emission
  FROM v_emission
  GROUP BY TRIM(country_name), year
),
gdp AS (
  SELECT TRIM(Country) AS country, year, SUM(Value) AS gdp_value
  FROM v_gdp
  GROUP BY TRIM(Country), year
)
SELECT e.country, e.year, e.total_emission, g.gdp_value,
       ROUND(e.total_emission / NULLIF(g.gdp_value,0), 8) AS emission_to_gdp_ratio
FROM emis e
JOIN gdp g ON e.country = g.country AND e.year = g.year
ORDER BY e.country, e.year;

--2.What is the energy consumption per capita for each country over the last decade?
WITH years AS (SELECT MAX(year) AS max_year FROM v_population),
 decade AS (SELECT max_year - 9 AS start_year FROM years)
SELECT TRIM(co.country) AS country, co.year,
       SUM(co.consumption) AS total_consumption,
       SUM(p.Value) AS population,
       ROUND(SUM(co.consumption) / NULLIF(SUM(p.Value),0), 8) AS consumption_per_capita
FROM v_consumption co
JOIN v_population p
  ON TRIM(co.country) = TRIM(p.countries) AND co.year = p.year
WHERE co.year BETWEEN (SELECT start_year FROM decade) AND (SELECT max_year FROM years)
GROUP BY TRIM(co.country), co.year
ORDER BY country, year;

--3.How does energy production per capita vary across countries?
SELECT TRIM(pr.country) AS country, pr.year,
       SUM(pr.production) AS total_production,
       SUM(p.Value) AS population,
       ROUND(SUM(pr.production) / NULLIF(SUM(p.Value),0), 8) AS production_per_capita
FROM v_production pr
JOIN v_population p ON TRIM(pr.country) = TRIM(p.countries) AND pr.year = p.year
GROUP BY TRIM(pr.country), pr.year
ORDER BY country, year;

--4.Which countries have the highest energy consumption relative to GDP?
WITH latest_gdp_year AS (SELECT MAX(year) AS y FROM v_gdp),
 latest_gdp AS (
   SELECT TRIM(Country) AS country, year, SUM(Value) AS gdp_value
   FROM v_gdp
   WHERE year = (SELECT y FROM latest_gdp_year)
   GROUP BY TRIM(Country), year
 ),
 latest_consumption AS (
   SELECT TRIM(country) AS country, year, SUM(consumption) AS total_consumption
   FROM v_consumption
   GROUP BY TRIM(country), year
 )
SELECT c.country, c.total_consumption, g.gdp_value,
       ROUND(c.total_consumption / NULLIF(g.gdp_value,0), 8) AS consumption_to_gdp_ratio
FROM latest_consumption c
JOIN latest_gdp g ON c.country = g.country AND c.year = g.year
ORDER BY consumption_to_gdp_ratio DESC
LIMIT 20;

---5.What is the correlation between GDP growth and energy production growth?
WITH gdp AS (
  SELECT TRIM(Country) AS country, year, SUM(Value) AS gdp_val
  FROM v_gdp GROUP BY TRIM(Country), year
),
prod AS (
  SELECT TRIM(country) AS country, year, SUM(production) AS prod_val
  FROM v_production GROUP BY TRIM(country), year
),
joined AS (
  SELECT g.country, g.year, g.gdp_val, p.prod_val
  FROM gdp g JOIN prod p ON g.country = p.country AND g.year = p.year
),
growth AS (
  SELECT country, year,
    (gdp_val - LAG(gdp_val) OVER (PARTITION BY country ORDER BY year))
      / NULLIF(LAG(gdp_val) OVER (PARTITION BY country ORDER BY year),0) AS gdp_growth,
    (prod_val - LAG(prod_val) OVER (PARTITION BY country ORDER BY year))
      / NULLIF(LAG(prod_val) OVER (PARTITION BY country ORDER BY year),0) AS prod_growth
  FROM joined
)
SELECT country,
  (COUNT(*)*SUM(gdp_growth*prod_growth) - SUM(gdp_growth)*SUM(prod_growth)) /
  ( SQRT( (COUNT(*)*SUM(gdp_growth*gdp_growth) - SUM(gdp_growth)*SUM(gdp_growth))
        * (COUNT(*)*SUM(prod_growth*prod_growth) - SUM(prod_growth)*SUM(prod_growth)) ) ) AS correlation
FROM growth
WHERE gdp_growth IS NOT NULL AND prod_growth IS NOT NULL
GROUP BY country
ORDER BY correlation DESC;


---------------- Global Comparisons---------------
1.What are the top 10 countries by population and how do their emissions compare?
WITH latest_pop_year AS (SELECT MAX(year) AS max_year FROM v_population),
pop_latest AS (
  SELECT TRIM(countries) AS country, SUM(Value) AS population
  FROM v_population
  WHERE year = (SELECT max_year FROM latest_pop_year)
  GROUP BY TRIM(countries)
),
emis_latest AS (
  SELECT TRIM(country_name) AS country, SUM(emission) AS total_emission
  FROM v_emission
  WHERE year = (SELECT MAX(year) FROM v_emission)
  GROUP BY TRIM(country_name)
)
SELECT p.country, p.population, COALESCE(e.total_emission,0) AS total_emission
FROM pop_latest 
LEFT JOIN emis_latest e ON p.country = e.country
ORDER BY p.population DESC
LIMIT 10;

--2.Which countries have improved (reduced) their per capita emissions the most over the last decade?
WITH years AS (SELECT MAX(year) AS max_year FROM v_emission),
 start_year AS (SELECT max_year - 9 AS min_year FROM years),
 pc AS (
  SELECT TRIM(country_name) AS country, year, AVG(per_capita_emission) AS pc_e
  FROM v_emission
  WHERE year BETWEEN (SELECT min_year FROM start_year) AND (SELECT max_year FROM years)
  GROUP BY TRIM(country_name), year
),
pivot AS (
  SELECT country,
         MAX(CASE WHEN year = (SELECT min_year FROM start_year) THEN pc_e END) AS start_pc,
         MAX(CASE WHEN year = (SELECT max_year FROM years) THEN pc_e END) AS end_pc
  FROM pc
  GROUP BY country
)
SELECT country, start_pc, end_pc,
       ROUND(start_pc - end_pc, 6) AS absolute_reduction,
       ROUND((start_pc - end_pc)/NULLIF(start_pc,0)*100,2) AS pct_reduction
FROM pivot
WHERE start_pc IS NOT NULL AND end_pc IS NOT NULL
ORDER BY absolute_reduction DESC
LIMIT 20;

----3.What is the global share (%) of emissions by country?
WITH latest AS (SELECT MAX(year) AS y FROM v_emission),
 country_totals AS (
   SELECT TRIM(country_name) AS country, SUM(emission) AS total_em
   FROM v_emission
   WHERE year = (SELECT y FROM latest)
   GROUP BY TRIM(country_name)
),
global_total AS (
   SELECT SUM(total_em) AS global_em FROM country_totals
)
SELECT c.country, c.total_em,
       ROUND(c.total_em / g.global_em * 100, 4) AS pct_share
FROM country_totals c CROSS JOIN global_total g
ORDER BY c.total_em DESC

---4.What is the global average GDP, emission, and population by year?

-- Global totals of emissions, GDP, and population by year
WITH e AS (
  SELECT year, SUM(emission) AS total_emission
  FROM v_emission
  GROUP BY year
),
g AS (
  SELECT year, SUM(Value) AS total_gdp
  FROM v_gdp
  GROUP BY year
),
p AS (
  SELECT year, SUM(Value) AS total_population
  FROM v_population
  GROUP BY year
)
SELECT 
  COALESCE(e.year, g.year, p.year) AS year,
  e.total_emission,
  g.total_gdp,
  p.total_population
FROM e
LEFT JOIN g ON e.year = g.year
LEFT JOIN p ON e.year = p.year
ORDER BY year;

-- Average per-country values by year
WITH e AS (
  SELECT year, AVG(total_em) AS avg_emission
  FROM (
    SELECT TRIM(country_name) AS country, year, SUM(emission) AS total_em
    FROM v_emission
    GROUP BY TRIM(country_name), year
  ) sub
  GROUP BY year
),
g AS (
  SELECT year, AVG(total_gdp) AS avg_gdp
  FROM (
    SELECT TRIM(Country) AS country, year, SUM(Value) AS total_gdp
    FROM v_gdp
    GROUP BY TRIM(Country), year
  ) sub
  GROUP BY year
),
p AS (
  SELECT year, AVG(total_pop) AS avg_population
  FROM (
    SELECT TRIM(countries) AS country, year, SUM(Value) AS total_pop
    FROM v_population
    GROUP BY TRIM(countries), year
  ) sub
  GROUP BY year
)
SELECT 
  COALESCE(e.year, g.year, p.year) AS year,
  e.avg_emission,
  g.avg_gdp,
  p.avg_population
FROM e
LEFT JOIN g ON e.year = g.year
LEFT JOIN p ON e.year = p.year
ORDER BY year;


        
 













