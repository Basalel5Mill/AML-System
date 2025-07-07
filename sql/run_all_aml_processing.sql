-- ============================================================================
-- COMPLETE AML PROCESSING - BigQuery SQL
-- Runs all AML detection algorithms in sequence
-- ============================================================================

-- Step 1: Create alerts table schema
CREATE TABLE IF NOT EXISTS `anlaytics-465216.aml_data.aml_alerts_level1` (
  alert_id INT64,
  customer_id STRING,
  alert_date DATE,
  alert_type STRING,
  risk_score INT64,
  description STRING,
  priority STRING,
  total_amount FLOAT64,
  status STRING,
  detection_date DATE
);

-- Step 2: Clear existing alerts
DELETE FROM `anlaytics-465216.aml_data.aml_alerts_level1` WHERE TRUE;

-- Step 3: Run Velocity Detection
INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
WITH velocity_analysis AS (
  SELECT 
    CONCAT(first, '_', last) as customer_id,
    trans_date_trans_time,
    amt,
    merchant,
    DATE(trans_date_trans_time) as transaction_date,
    TIMESTAMP_DIFF(
      trans_date_trans_time,
      LAG(trans_date_trans_time) OVER (
        PARTITION BY CONCAT(first, '_', last) 
        ORDER BY trans_date_trans_time
      ),
      MINUTE
    ) as minutes_since_last
  FROM `anlaytics-465216.aml_data.credit_card_transactions`
),
rapid_transactions AS (
  SELECT 
    customer_id,
    transaction_date,
    COUNT(*) as rapid_transaction_count,
    SUM(amt) as total_amount,
    MIN(minutes_since_last) as min_time_diff
  FROM velocity_analysis
  WHERE minutes_since_last <= 5
  GROUP BY customer_id, transaction_date
  HAVING COUNT(*) >= 5
)
SELECT 
  ROW_NUMBER() OVER (ORDER BY rapid_transaction_count DESC) as alert_id,
  customer_id,
  transaction_date as alert_date,
  'VELOCITY' as alert_type,
  LEAST(rapid_transaction_count * 20, 100) as risk_score,
  CONCAT('Customer made ', rapid_transaction_count, ' rapid transactions totaling $', FORMAT('%\'.0f', total_amount)) as description,
  CASE 
    WHEN rapid_transaction_count * 20 >= 80 THEN 'HIGH'
    WHEN rapid_transaction_count * 20 >= 50 THEN 'MEDIUM'
    ELSE 'LOW'
  END as priority,
  total_amount,
  'OPEN' as status,
  CURRENT_DATE() as detection_date
FROM rapid_transactions;

-- Step 4: Run Structuring Detection
INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
WITH structuring_analysis AS (
  SELECT 
    CONCAT(first, '_', last) as customer_id,
    DATE(trans_date_trans_time) as transaction_date,
    COUNT(*) as transaction_count,
    SUM(amt) as total_amount
  FROM `anlaytics-465216.aml_data.credit_card_transactions`
  WHERE amt BETWEEN 9000 AND 9999
  GROUP BY customer_id, transaction_date
  HAVING COUNT(*) >= 2
)
SELECT 
  (SELECT IFNULL(MAX(alert_id), 0) FROM `anlaytics-465216.aml_data.aml_alerts_level1`) + 
  ROW_NUMBER() OVER (ORDER BY transaction_count DESC) as alert_id,
  customer_id,
  transaction_date as alert_date,
  'STRUCTURING' as alert_type,
  LEAST(transaction_count * 25, 100) as risk_score,
  CONCAT('Customer made ', transaction_count, ' transactions totaling $', FORMAT('%\'.0f', total_amount), ' just under $10,000 threshold') as description,
  CASE 
    WHEN transaction_count * 25 >= 80 THEN 'HIGH'
    WHEN transaction_count * 25 >= 50 THEN 'MEDIUM'
    ELSE 'LOW'
  END as priority,
  total_amount,
  'OPEN' as status,
  CURRENT_DATE() as detection_date
FROM structuring_analysis;

-- Step 5: Run Geographic Detection
INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
WITH geographic_analysis AS (
  SELECT 
    CONCAT(first, '_', last) as customer_id,
    DATE(trans_date_trans_time) as transaction_date,
    COUNT(DISTINCT state) as unique_states,
    COUNT(DISTINCT city) as unique_cities,
    SUM(amt) as total_amount
  FROM `anlaytics-465216.aml_data.credit_card_transactions`
  GROUP BY customer_id, transaction_date
  HAVING COUNT(DISTINCT state) > 2 OR (COUNT(DISTINCT city) > 5 AND COUNT(*) > 5)
)
SELECT 
  (SELECT IFNULL(MAX(alert_id), 0) FROM `anlaytics-465216.aml_data.aml_alerts_level1`) + 
  ROW_NUMBER() OVER (ORDER BY unique_states DESC) as alert_id,
  customer_id,
  transaction_date as alert_date,
  'GEOGRAPHIC' as alert_type,
  LEAST((unique_states * 15) + (unique_cities * 3), 100) as risk_score,
  CONCAT('Customer transacted in ', unique_states, ' states and ', unique_cities, ' cities in one day') as description,
  CASE 
    WHEN (unique_states * 15) + (unique_cities * 3) >= 80 THEN 'HIGH'
    WHEN (unique_states * 15) + (unique_cities * 3) >= 50 THEN 'MEDIUM'
    ELSE 'LOW'
  END as priority,
  total_amount,
  'OPEN' as status,
  CURRENT_DATE() as detection_date
FROM geographic_analysis;

-- Step 6: Generate Customer Risk Profiles (runs the full customer_risk_profiles.sql)

-- Final: Show summary
SELECT 
  alert_type,
  priority,
  COUNT(*) as alert_count,
  SUM(total_amount) as total_financial_impact
FROM `anlaytics-465216.aml_data.aml_alerts_level1`
GROUP BY alert_type, priority
ORDER BY alert_type, priority;