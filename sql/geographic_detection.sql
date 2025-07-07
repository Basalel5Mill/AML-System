-- ============================================================================
-- GEOGRAPHIC ANOMALY DETECTION - BigQuery SQL
-- Detects transactions across multiple states/cities in one day
-- ============================================================================

INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
WITH geographic_analysis AS (
  SELECT 
    CONCAT(first, '_', last) as customer_id,
    DATE(trans_date_trans_time) as transaction_date,
    COUNT(DISTINCT state) as unique_states,
    COUNT(DISTINCT city) as unique_cities,
    COUNT(*) as transaction_count,
    SUM(amt) as total_amount,
    STRING_AGG(DISTINCT state, ', ') as states_list,
    STRING_AGG(DISTINCT city, ', ') as cities_list
  FROM `anlaytics-465216.aml_data.credit_card_transactions`
  GROUP BY customer_id, transaction_date
  HAVING 
    COUNT(DISTINCT state) > 2 OR 
    (COUNT(DISTINCT city) > 5 AND COUNT(*) > 5)
)

SELECT 
  (SELECT IFNULL(MAX(alert_id), 0) FROM `anlaytics-465216.aml_data.aml_alerts_level1`) + 
  ROW_NUMBER() OVER (ORDER BY unique_states DESC, unique_cities DESC) as alert_id,
  customer_id,
  transaction_date as alert_date,
  'GEOGRAPHIC' as alert_type,
  LEAST((unique_states * 15) + (unique_cities * 3), 100) as risk_score,
  CONCAT(
    'Customer transacted in ', unique_states, ' states and ', 
    unique_cities, ' cities in one day'
  ) as description,
  CASE 
    WHEN (unique_states * 15) + (unique_cities * 3) >= 80 THEN 'HIGH'
    WHEN (unique_states * 15) + (unique_cities * 3) >= 50 THEN 'MEDIUM'
    ELSE 'LOW'
  END as priority,
  total_amount,
  'OPEN' as status,
  CURRENT_DATE() as detection_date
FROM geographic_analysis
ORDER BY risk_score DESC;