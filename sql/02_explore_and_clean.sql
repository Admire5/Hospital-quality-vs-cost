/* =====================================================================
   Project:  Hospital Quality vs. Cost (Project 02)
   Script:   02_explore_and_clean.sql
   Purpose:  Part A - profile the three raw tables
             Part B - clean each table and pivot the readmission measures
             Part C - join everything into one analysis table
             Part D - sanity checks
   Author:   Siloyiso Admire Tshababa

   HOW TO RUN:
   - Part A: one query at a time (Ctrl+Enter). Read each result.
   - Parts B and C: select them and run with the plain lightning bolt.
   - Part D: one query at a time.
   ===================================================================== */

USE hospital_quality;


/* =====================================================================
   PART A - PROFILE
   ===================================================================== */

-- A1. What types of hospitals are there? (We will focus on acute care.)
SELECT hospital_type, COUNT(*) AS hospitals
FROM hospitals_raw
GROUP BY hospital_type
ORDER BY hospitals DESC;


-- A2. How much is missing in the columns we need?
SELECT
    COUNT(*)                                  AS hospitals,
    SUM(overall_rating = 'Not Available')     AS rating_missing,
    SUM(mort_better    = 'Not Available')     AS mortality_missing,
    SUM(readm_worse    = 'Not Available')     AS readmission_missing
FROM hospitals_raw;

SELECT
    COUNT(*)                         AS hospitals,
    SUM(score = 'Not Available')     AS spending_missing
FROM spending_raw;


-- A3. Who is missing a star rating? (Missing is rarely random.)
SELECT hospital_type,
       COUNT(*) AS hospitals,
       ROUND(100.0 * AVG(overall_rating = 'Not Available'), 1) AS pct_rating_missing
FROM hospitals_raw
GROUP BY hospital_type
ORDER BY hospitals DESC;


-- A4. The readmission measures: one row per hospital PER measure.
--     These are the rows we will turn into columns in Part B.
SELECT measure_id,
       MIN(measure_name)                                    AS measure_name,
       SUM(score <> 'Not Available')                        AS hospitals_with_score
FROM unplanned_visits_raw
GROUP BY measure_id
ORDER BY measure_id;


-- A5. Inconsistent labels: the same category written different ways.
SELECT compared_to_national, COUNT(*) AS n
FROM unplanned_visits_raw
GROUP BY compared_to_national
ORDER BY n DESC;


-- A6. Only one kind of text hides in the number columns: 'Not Available'.
--     This query should return just that one value.
SELECT score, COUNT(*) AS n
FROM spending_raw
WHERE score NOT REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
GROUP BY score;


-- A7. Spending score distribution (1.00 = national median)
SELECT MIN(CAST(score AS DECIMAL(4,2))) AS min_score,
       ROUND(AVG(CAST(score AS DECIMAL(4,2))), 2) AS avg_score,
       MAX(CAST(score AS DECIMAL(4,2))) AS max_score
FROM spending_raw
WHERE score <> 'Not Available';


/* =====================================================================
   PART B - CLEAN EACH TABLE
   Key technique:  NULLIF(column, 'Not Available')
     returns NULL when the value is 'Not Available', otherwise the value.
     Then CAST(... AS ...) turns the text into a real number.
   ===================================================================== */

-- B1. Hospitals: acute care only, numbers converted, ownership grouped
DROP TABLE IF EXISTS hospitals_clean;

CREATE TABLE hospitals_clean AS
SELECT
    facility_id,
    facility_name,
    city,
    state,
    county,
    hospital_ownership,
    CASE
        WHEN hospital_ownership LIKE 'Voluntary non-profit%' THEN 'Non-profit'
        WHEN hospital_ownership = 'Proprietary'              THEN 'For-profit'
        WHEN hospital_ownership LIKE 'Government%'           THEN 'Government'
        ELSE 'Other'
    END                                                              AS ownership_group,
    emergency_services,
    CAST(NULLIF(overall_rating, 'Not Available') AS UNSIGNED)        AS star_rating,
    CAST(NULLIF(mort_better,    'Not Available') AS UNSIGNED)        AS mortality_better,
    CAST(NULLIF(mort_worse,     'Not Available') AS UNSIGNED)        AS mortality_worse,
    CAST(NULLIF(safety_better,  'Not Available') AS UNSIGNED)        AS safety_better,
    CAST(NULLIF(safety_worse,   'Not Available') AS UNSIGNED)        AS safety_worse,
    CAST(NULLIF(readm_better,   'Not Available') AS UNSIGNED)        AS readmission_better,
    CAST(NULLIF(readm_worse,    'Not Available') AS UNSIGNED)        AS readmission_worse
FROM hospitals_raw
WHERE hospital_type = 'Acute Care Hospitals';

ALTER TABLE hospitals_clean ADD PRIMARY KEY (facility_id);


-- B2. Spending: one number per hospital
DROP TABLE IF EXISTS spending_clean;

CREATE TABLE spending_clean AS
SELECT
    facility_id,
    CAST(NULLIF(score, 'Not Available') AS DECIMAL(4,2)) AS mspb_score
FROM spending_raw;

ALTER TABLE spending_clean ADD PRIMARY KEY (facility_id);


-- B3. Readmissions: PIVOT from long (many rows per hospital) to wide (one row).
--     For each hospital, CASE picks out the score of one measure and leaves
--     NULL for the others. MAX() then keeps the single non-NULL value.
DROP TABLE IF EXISTS readmissions_wide;

CREATE TABLE readmissions_wide AS
SELECT
    facility_id,
    MAX(CASE WHEN measure_id = 'READM_30_HF'       THEN CAST(NULLIF(score, 'Not Available') AS DECIMAL(5,2)) END) AS readm_heart_failure,
    MAX(CASE WHEN measure_id = 'READM_30_AMI'      THEN CAST(NULLIF(score, 'Not Available') AS DECIMAL(5,2)) END) AS readm_heart_attack,
    MAX(CASE WHEN measure_id = 'READM_30_PN'       THEN CAST(NULLIF(score, 'Not Available') AS DECIMAL(5,2)) END) AS readm_pneumonia,
    MAX(CASE WHEN measure_id = 'READM_30_COPD'     THEN CAST(NULLIF(score, 'Not Available') AS DECIMAL(5,2)) END) AS readm_copd,
    MAX(CASE WHEN measure_id = 'READM_30_HIP_KNEE' THEN CAST(NULLIF(score, 'Not Available') AS DECIMAL(5,2)) END) AS readm_hip_knee,
    -- How the heart failure rate compares with the nation, with the
    -- inconsistent capitalisation fixed by comparing in lower case
    MAX(CASE WHEN measure_id = 'READM_30_HF' THEN
        CASE LOWER(compared_to_national)
            WHEN 'better than the national rate'        THEN 'Better'
            WHEN 'no different than the national rate'  THEN 'No different'
            WHEN 'worse than the national rate'         THEN 'Worse'
            WHEN 'number of cases too small'            THEN 'Too few cases'
            ELSE 'Not available'
        END
    END)                                                                                                           AS hf_vs_national
FROM unplanned_visits_raw
GROUP BY facility_id;

ALTER TABLE readmissions_wide ADD PRIMARY KEY (facility_id);


/* =====================================================================
   PART C - JOIN INTO ONE ANALYSIS TABLE
   LEFT JOIN keeps every acute care hospital, even if it has no spending
   or readmission data (those columns will simply be NULL).
   ===================================================================== */
DROP TABLE IF EXISTS hospital_analysis;

CREATE TABLE hospital_analysis AS
SELECT
    h.*,
    s.mspb_score,
    CASE
        WHEN s.mspb_score IS NULL  THEN 'No data'
        WHEN s.mspb_score <  0.95  THEN 'Lower spending (<0.95)'
        WHEN s.mspb_score <= 1.05  THEN 'Near national (0.95-1.05)'
        ELSE                            'Higher spending (>1.05)'
    END                                                   AS spending_group,
    r.readm_heart_failure,
    r.readm_heart_attack,
    r.readm_pneumonia,
    r.readm_copd,
    r.readm_hip_knee,
    r.hf_vs_national,
    CASE WHEN h.state = 'NY' THEN 1 ELSE 0 END            AS is_new_york
FROM hospitals_clean h
LEFT JOIN spending_clean    s ON s.facility_id = h.facility_id
LEFT JOIN readmissions_wide r ON r.facility_id = h.facility_id;

ALTER TABLE hospital_analysis ADD PRIMARY KEY (facility_id);


/* =====================================================================
   PART D - SANITY CHECKS
   ===================================================================== */

-- D1. The funnel: how many hospitals have each piece of data?
--     Expected (approx.): 3,107 acute care | ~2,600 with rating + spending
--                         NY: 128 acute care | ~122 with rating + spending
SELECT 'All acute care hospitals'        AS stage,
       COUNT(*) AS us, SUM(is_new_york) AS ny
FROM hospital_analysis
UNION ALL
SELECT 'With a star rating',
       COUNT(*), SUM(is_new_york)
FROM hospital_analysis WHERE star_rating IS NOT NULL
UNION ALL
SELECT 'With rating AND spending score',
       COUNT(*), SUM(is_new_york)
FROM hospital_analysis WHERE star_rating IS NOT NULL AND mspb_score IS NOT NULL;


-- D2. The pivot worked: one row per hospital, five readmission columns
SELECT facility_name, state, star_rating, mspb_score,
       readm_heart_failure, readm_pneumonia, hf_vs_national
FROM hospital_analysis
WHERE is_new_york = 1 AND star_rating IS NOT NULL
ORDER BY facility_name
LIMIT 10;


-- D3. First look at the big question: does spending relate to star rating?
SELECT spending_group,
       COUNT(*)                      AS hospitals,
       ROUND(AVG(star_rating), 2)    AS avg_star_rating,
       ROUND(AVG(readm_heart_failure), 1) AS avg_hf_readmission_pct
FROM hospital_analysis
WHERE star_rating IS NOT NULL
GROUP BY spending_group
ORDER BY MIN(mspb_score);
