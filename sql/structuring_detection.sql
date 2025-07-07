-- ============================================================================
-- STRUCTURING DETECTION - BigQuery SQL  
-- Detects transactions just under $10,000 threshold
-- ============================================================================

INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
WITH structuring_analysis AS (
  SELECT 
    CONCAT(first, '_', last) as customer_id,
    DATE(trans_date_trans_time) as transaction_date,
    COUNT(*) as transaction_count,
    SUM(amt) as total_amount,
    AVG(amt) as avg_amount,
    STRING_AGG(DISTINCT merchant, ', ') as merchants
  FROM `anlaytics-465216.aml_data.credit_card_transactions`
  WHERE amt BETWEEN 9000 AND 9999  -- Just under $10K threshold
  GROUP BY customer_id, transaction_date
  HAVING COUNT(*) >= 2  -- Multiple transactions in same day
)

SELECT 
  (SELECT MAX(alert_id) FROM `anlaytics-465216.aml_data.aml_alerts_level1`) + 
  ROW_NUMBER() OVER (ORDER BY transaction_count DESC) as alert_id,
  customer_id,
  transaction_date as alert_date,
  'STRUCTURING' as alert_type,
  LEAST(transaction_count * 25, 100) as risk_score,
  CONCAT(
    'Customer made ', transaction_count, 
    ' transactions totaling $', FORMAT('%\'.0f', total_amount),
    ' just under $10,000 threshold'
  ) as description,
  CASE 
    WHEN transaction_count * 25 >= 80 THEN 'HIGH'
    WHEN transaction_count * 25 >= 50 THEN 'MEDIUM'
    ELSE 'LOW'
  END as priority,
  total_amount,
  'OPEN' as status,
  CURRENT_DATE() as detection_date
FROM structuring_analysis
ORDER BY risk_score DESC;