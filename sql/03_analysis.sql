
USE hospital_quality;

-- ANALYSIS SET

CREATE OR REPLACE VIEW analysis_set AS
SELECT *
FROM hospital_analysis
WHERE star_rating IS NOT NULL
  AND mspb_score  IS NOT NULL;
select * from hospital_analysis;

-- Q1. Baseline: United States vs New York
SELECT
    CASE WHEN is_new_york = 1 THEN 'New York' ELSE 'Rest of US' END AS area,
    COUNT(*)   AS hospitals,
    ROUND(AVG(star_rating), 2)  AS avg_star_rating,
    ROUND(AVG(mspb_score), 3) AS avg_spending_ratio,
    ROUND(AVG(readm_heart_failure), 1)  AS avg_hf_readmission_pct
FROM analysis_set
GROUP BY area;


-- Q2. Spending group vs quality 
SELECT
    spending_group,
    COUNT(*)     AS hospitals,
    ROUND(AVG(star_rating), 2)  AS avg_star_rating,
    ROUND(100.0 * AVG(star_rating >= 4), 1)  AS pct_4_or_5_stars,
    ROUND(100.0 * AVG(star_rating <= 2), 1) AS pct_1_or_2_stars,
    ROUND(AVG(readm_heart_failure), 1)  AS avg_hf_readmission_pct
FROM analysis_set
GROUP BY spending_group
ORDER BY MIN(mspb_score);


/* Q3. Correlation between spending and quality 
   MySQL has no CORR() function, so we use the Pearson formula. */
                                       
SELECT
    CASE WHEN is_new_york = 1 THEN 'New York' ELSE 'Rest of US' END AS area,
    COUNT(*) AS hospitals,
    ROUND( (AVG(mspb_score * star_rating) - AVG(mspb_score) * AVG(star_rating))
           / (STDDEV_POP(mspb_score) * STDDEV_POP(star_rating)), 3)   AS r_spending_vs_stars
FROM analysis_set
GROUP BY area;

-- Same idea for spending vs heart failure readmission (only hospitals with a rate)
SELECT
    COUNT(*) AS hospitals,
    ROUND( (AVG(mspb_score * readm_heart_failure) - AVG(mspb_score) * AVG(readm_heart_failure))
           / (STDDEV_POP(mspb_score) * STDDEV_POP(readm_heart_failure)), 3) AS r_spending_vs_hf_readm,
    ROUND( (AVG(star_rating * readm_heart_failure) - AVG(star_rating) * AVG(readm_heart_failure))
           / (STDDEV_POP(star_rating) * STDDEV_POP(readm_heart_failure)), 3) AS r_stars_vs_hf_readm
FROM analysis_set
WHERE readm_heart_failure IS NOT NULL;


-- Q4. Looking at it from the quality side: what do 1- to 5-star hospitals spend?
SELECT
    star_rating,
    COUNT(*)  AS hospitals,
    ROUND(AVG(mspb_score), 3) AS avg_spending_ratio,
    ROUND(AVG(readm_heart_failure), 1)  AS avg_hf_readmission_pct,
    ROUND(AVG(mortality_worse), 2)  AS avg_mortality_measures_worse
FROM analysis_set
GROUP BY star_rating
ORDER BY star_rating;


-- Q5. Ownership: non-profit vs for-profit vs government 
SELECT
    ownership_group,
    COUNT(*)  AS hospitals,
    ROUND(AVG(star_rating), 2)  AS avg_star_rating,
    ROUND(AVG(mspb_score), 3) AS avg_spending_ratio,
    ROUND(100.0 * AVG(mspb_score > 1.05), 1) AS pct_higher_spending
FROM analysis_set
GROUP BY ownership_group
ORDER BY hospitals DESC;


/* Q6. Star rating distribution: New York vs rest of US
   Conditional aggregation again: one column per area.  */
SELECT
    star_rating,
    SUM(is_new_york = 1)                                             AS ny_hospitals,
    ROUND(100.0 * SUM(is_new_york = 1) / SUM(SUM(is_new_york = 1)) OVER (), 1) AS ny_pct,
    SUM(is_new_york = 0)   AS rest_hospitals,
    ROUND(100.0 * SUM(is_new_york = 0) / SUM(SUM(is_new_york = 0)) OVER (), 1) AS rest_pct
FROM analysis_set
GROUP BY star_rating
ORDER BY star_rating;



  -- Q7. NEW YORK VALUE MATRIX
  
WITH ny AS (
    SELECT *,
        CASE WHEN star_rating >= 4 THEN 'High quality'
             WHEN star_rating  = 3 THEN 'Average quality'
             ELSE   'Low quality' END   AS quality_level,
        CASE WHEN mspb_score < 1.00 THEN 'Lower cost'
             ELSE                        'Higher cost' END  AS cost_level
    FROM analysis_set
    WHERE is_new_york = 1
)
SELECT
    quality_level,
    SUM(cost_level = 'Lower cost')  AS lower_cost,
    SUM(cost_level = 'Higher cost') AS higher_cost,
    COUNT(*)   AS total
FROM ny
GROUP BY quality_level
ORDER BY FIELD(quality_level, 'High quality', 'Average quality', 'Low quality');


/* Q8. New York's highest-value hospitals: high quality, lower cost ----- */
SELECT
    RANK() OVER (ORDER BY star_rating DESC, mspb_score ASC) AS value_rank,
    facility_name,
    city,
    star_rating,
    mspb_score,
    readm_heart_failure
FROM analysis_set
WHERE is_new_york = 1
  AND star_rating >= 4
  AND mspb_score  < 1.00
ORDER BY value_rank;


/* Q9. Where to look for improvement: NY hospitals with low quality AND higher cost */
SELECT
    facility_name,
    city,
    star_rating,
    mspb_score,
    readm_heart_failure
FROM analysis_set
WHERE is_new_york = 1
  AND star_rating <= 2
  AND mspb_score  >= 1.00
ORDER BY mspb_score DESC;
