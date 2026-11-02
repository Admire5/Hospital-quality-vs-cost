/* =====================================================================
   Project:  Hospital Quality vs. Cost (Project 02)
   Script:   01_create_and_load.sql
   Purpose:  Create the database and load three CMS Provider Data
             Catalog files into raw tables.
   Source:   CMS Provider Data Catalog - data.cms.gov/provider-data
             1. Hospital General Information           (1 row per hospital)
             2. Medicare Spending Per Beneficiary - Hospital (1 row per hospital)
             3. Unplanned Hospital Visits - Hospital    (1 row per hospital per measure)
   Author:   Siloyiso Admire Tshababa

   NOTES ON THE RAW FILES (from profiling before loading):
   - Facility ID is TEXT: it has leading zeros (010001) and some IDs
     contain letters (01014F). Storing it as a number would break it.
   - CMS writes 'Not Available' inside numeric columns, so every column
     is loaded as text here. Conversion to numbers happens in script 02.
   - Some names/addresses contain commas inside quotes -> ENCLOSED BY '"'.
   - Files use Windows line endings -> LINES TERMINATED BY '\r\n'.
   - Columns we don't need are read into @skip so LOAD DATA can still
     match every column in the file.
   ===================================================================== */

-- Needed again if MySQL restarted since Project 01
SET GLOBAL local_infile = 1;

CREATE DATABASE IF NOT EXISTS hospital_quality;
USE hospital_quality;


/* ---------------------------------------------------------------------
   1. HOSPITAL GENERAL INFORMATION  (one row per hospital)
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS hospitals_raw;

CREATE TABLE hospitals_raw (
    facility_id            VARCHAR(10) PRIMARY KEY,
    facility_name          VARCHAR(100),
    address                VARCHAR(100),
    city                   VARCHAR(50),
    state                  CHAR(2),
    zip_code               VARCHAR(10),
    county                 VARCHAR(50),
    hospital_type          VARCHAR(50),
    hospital_ownership     VARCHAR(60),
    emergency_services     VARCHAR(5),
    overall_rating         VARCHAR(20),   -- '1'-'5' or 'Not Available'
    overall_rating_footnote VARCHAR(20),
    mort_better            VARCHAR(20),   -- # mortality measures better than national
    mort_worse             VARCHAR(20),
    safety_better          VARCHAR(20),   -- # safety measures better than national
    safety_worse           VARCHAR(20),
    readm_better           VARCHAR(20),   -- # readmission measures better than national
    readm_worse            VARCHAR(20)
);

LOAD DATA LOCAL INFILE 'C:/Users/tsilo/Downloads/Portfolio/Hospital-quality-vs-cost/data/raw/Hospital_General_Information.csv'
INTO TABLE hospitals_raw
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(facility_id, facility_name, address, city, state, zip_code, county,
 @skip,                                    -- Telephone Number
 hospital_type, hospital_ownership, emergency_services,
 @skip,                                    -- Birthing friendly designation
 overall_rating, overall_rating_footnote,
 @skip, @skip, mort_better, @skip, mort_worse, @skip,       -- MORT group
 @skip, @skip, safety_better, @skip, safety_worse, @skip,   -- Safety group
 @skip, @skip, readm_better, @skip, readm_worse, @skip,     -- READM group
 @skip, @skip, @skip,                      -- Patient experience group
 @skip, @skip, @skip);                     -- Timely & effective care group


/* ---------------------------------------------------------------------
   2. MEDICARE SPENDING PER BENEFICIARY (MSPB)  (one row per hospital)
   Score = hospital spending per episode / national median.
   1.00 = national median; 1.10 = 10% more expensive; 0.90 = 10% cheaper.
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS spending_raw;

CREATE TABLE spending_raw (
    facility_id   VARCHAR(10) PRIMARY KEY,
    state         CHAR(2),
    measure_id    VARCHAR(20),
    score         VARCHAR(20),     -- e.g. '0.99' or 'Not Available'
    footnote      VARCHAR(20),
    start_date    VARCHAR(10),
    end_date      VARCHAR(10)
);

LOAD DATA LOCAL INFILE 'C:/Users/tsilo/Downloads/Portfolio/Hospital-quality-vs-cost/data/raw/Medicare_Hospital_Spending_Per_Patient-Hospital.csv'
INTO TABLE spending_raw
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(facility_id, @skip, @skip, @skip, state, @skip, @skip, @skip,   -- name..phone (already in hospitals_raw)
 measure_id, @skip, score, footnote, start_date, end_date);


/* ---------------------------------------------------------------------
   3. UNPLANNED HOSPITAL VISITS  (one row per hospital PER MEASURE)
   14 measures per hospital, e.g. READM_30_HF = heart failure
   30-day readmission rate (%).
   --------------------------------------------------------------------- */
DROP TABLE IF EXISTS unplanned_visits_raw;

CREATE TABLE unplanned_visits_raw (
    facility_id            VARCHAR(10),
    measure_id             VARCHAR(30),
    measure_name           VARCHAR(120),
    compared_to_national   VARCHAR(50),
    denominator            VARCHAR(20),
    score                  VARCHAR(20),
    lower_estimate         VARCHAR(20),
    higher_estimate        VARCHAR(20),
    footnote               VARCHAR(20),
    start_date             VARCHAR(10),
    end_date               VARCHAR(10),
    PRIMARY KEY (facility_id, measure_id)    -- one row per hospital + measure
);

LOAD DATA LOCAL INFILE 'C:/Users/tsilo/Downloads/Portfolio/Hospital-quality-vs-cost/data/raw/Unplanned_Hospital_Visits-Hospital.csv'
INTO TABLE unplanned_visits_raw
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(facility_id, @skip, @skip, @skip, @skip, @skip, @skip, @skip,  -- name..phone
 measure_id, measure_name, compared_to_national, denominator, score,
 lower_estimate, higher_estimate,
 @skip, @skip,                                                   -- Number of Patients / Returned
 footnote, start_date, end_date);


/* ---------------------------------------------------------------------
   4. SANITY CHECKS
   --------------------------------------------------------------------- */
-- Expected: 5,419 | 4,626 | 67,060
SELECT 'hospitals_raw'        AS table_name, COUNT(*) AS row_count FROM hospitals_raw
UNION ALL
SELECT 'spending_raw',                       COUNT(*)              FROM spending_raw
UNION ALL
SELECT 'unplanned_visits_raw',               COUNT(*)              FROM unplanned_visits_raw;

-- Expected: 192 hospitals in New York
SELECT COUNT(*) AS ny_hospitals FROM hospitals_raw WHERE state = 'NY';

-- Expected: 14 measures, each with 4,790 rows
SELECT measure_id, COUNT(*) AS hospitals
FROM unplanned_visits_raw
GROUP BY measure_id
ORDER BY measure_id;
