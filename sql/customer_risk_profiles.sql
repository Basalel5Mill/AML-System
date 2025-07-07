-- ============================================================================
-- CUSTOMER RISK PROFILES - BigQuery SQL
-- Creates comprehensive customer risk assessment
-- ============================================================================

CREATE OR REPLACE TABLE `anlaytics-465216.aml_data.customer_risk_profiles_level2` AS
WITH customer_metrics AS (
  SELECT 
    CONCAT(first, '_', last) as customer_id,
    COUNT(*) as total_transactions,
    SUM(amt) as total_amount,
    AVG(amt) as avg_amount,
    MAX(amt) as max_amount,
    COUNT(DISTINCT merchant) as unique_merchants,
    COUNT(DISTINCT category) as unique_categories,
    COUNT(DISTINCT state) as unique_states,
    
    -- Risk indicators
    SUM(CASE WHEN amt > 5000 THEN 1 ELSE 0 END) as high_amount_transactions,
    SUM(CASE WHEN amt IN (100, 200, 500, 1000, 2000, 5000, 10000) THEN 1 ELSE 0 END) as round_amount_transactions,
    
    -- Time patterns
    COUNT(CASE WHEN EXTRACT(HOUR FROM trans_date_trans_time) BETWEEN 22 AND 6 THEN 1 END) as night_transactions,
    COUNT(CASE WHEN EXTRACT(DAYOFWEEK FROM trans_date_trans_time) IN (1, 7) THEN 1 END) as weekend_transactions,
    
    MIN(DATE(trans_date_trans_time)) as first_transaction_date,
    MAX(DATE(trans_date_trans_time)) as last_transaction_date
    
  FROM `anlaytics-465216.aml_data.credit_card_transactions`
  GROUP BY customer_id
),

customer_alerts AS (
  SELECT 
    customer_id,
    COUNT(*) as total_alerts,
    SUM(CASE WHEN priority = 'HIGH' THEN 1 ELSE 0 END) as high_priority_alerts,
    AVG(risk_score) as avg_risk_score,
    MAX(risk_score) as max_risk_score
  FROM `anlaytics-465216.aml_data.aml_alerts_level1`
  GROUP BY customer_id
)

SELECT 
  m.customer_id,
  m.total_transactions,
  m.total_amount,
  m.avg_amount,
  m.max_amount,
  m.unique_merchants,
  m.unique_states,
  
  -- Risk score calculation
  LEAST(
    (IFNULL(a.total_alerts, 0) * 20) +
    (m.high_amount_transactions * 5) +
    (m.round_amount_transactions * 3) +
    (m.night_transactions * 2) +
    (m.unique_states * 10),
    100
  ) as risk_score,
  
  -- Risk category
  CASE 
    WHEN LEAST(
      (IFNULL(a.total_alerts, 0) * 20) +
      (m.high_amount_transactions * 5) +
      (m.round_amount_transactions * 3) +
      (m.night_transactions * 2) +
      (m.unique_states * 10),
      100
    ) >= 80 THEN 'CRITICAL'
    WHEN LEAST(
      (IFNULL(a.total_alerts, 0) * 20) +
      (m.high_amount_transactions * 5) +
      (m.round_amount_transactions * 3) +
      (m.night_transactions * 2) +
      (m.unique_states * 10),
      100
    ) >= 60 THEN 'HIGH'
    WHEN LEAST(
      (IFNULL(a.total_alerts, 0) * 20) +
      (m.high_amount_transactions * 5) +
      (m.round_amount_transactions * 3) +
      (m.night_transactions * 2) +
      (m.unique_states * 10),
      100
    ) >= 40 THEN 'MEDIUM'
    ELSE 'LOW'
  END as risk_category,
  
  IFNULL(a.total_alerts, 0) as total_alerts,
  IFNULL(a.high_priority_alerts, 0) as high_priority_alerts,
  IFNULL(a.max_risk_score, 0) as max_alert_risk_score,
  
  m.first_transaction_date,
  m.last_transaction_date,
  CURRENT_TIMESTAMP() as profile_generated_date

FROM customer_metrics m
LEFT JOIN customer_alerts a ON m.customer_id = a.customer_id
ORDER BY risk_score DESC;