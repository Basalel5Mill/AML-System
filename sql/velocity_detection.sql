-- ============================================================================
-- VELOCITY DETECTION - BigQuery SQL
-- Detects rapid transactions within 5 minutes
-- ============================================================================

CREATE OR REPLACE TABLE `anlaytics-465216.aml_data.aml_alerts_level1` AS
WITH velocity_analysis AS (
  SELECT 
    CONCAT(first, '_', last) as customer_id,
    trans_date_trans_time,
    amt,
    merchant,
    DATE(trans_date_trans_time) as transaction_date,
    
    -- Calculate time difference from previous transaction
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
    AVG(amt) as avg_amount,
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
  CONCAT(
    'Customer made ', rapid_transaction_count, 
    ' rapid transactions (within 5 minutes) totaling $', 
    FORMAT('%\'.0f', total_amount)
  ) as description,
  CASE 
    WHEN rapid_transaction_count * 20 >= 80 THEN 'HIGH'
    WHEN rapid_transaction_count * 20 >= 50 THEN 'MEDIUM'
    ELSE 'LOW'
  END as priority,
  total_amount,
  'OPEN' as status,
  CURRENT_DATE() as detection_date
FROM rapid_transactions
ORDER BY risk_score DESC;