-- ============================================================================
-- INCREMENTAL AML PROCESSING - Processes only new data automatically
-- Runs every 30 minutes to detect and process new transactions
-- ============================================================================

DECLARE last_processed_time TIMESTAMP;
DECLARE processing_start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
DECLARE new_records_count INT64;
DECLARE alerts_created INT64 DEFAULT 0;

-- Get last processed timestamp
SET last_processed_time = (
  SELECT last_processed_timestamp 
  FROM `anlaytics-465216.aml_data.processing_metadata` 
  WHERE process_name = 'aml_processing'
);

-- Check if there are new records to process
SET new_records_count = (
  SELECT COUNT(*)
  FROM `anlaytics-465216.aml_data.credit_card_transactions`
  WHERE trans_date_trans_time > last_processed_time
);

-- Exit early if no new records
IF new_records_count = 0 THEN
  -- Update status to show no new data
  UPDATE `anlaytics-465216.aml_data.processing_metadata`
  SET 
    status = 'NO_NEW_DATA',
    updated_at = CURRENT_TIMESTAMP()
  WHERE process_name = 'aml_processing';
  
  SELECT 'No new transactions to process' as message;
  
ELSE
  -- Process new transactions
  
  -- ===========================================
  -- 1. VELOCITY DETECTION
  -- ===========================================
  INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
  WITH new_transactions AS (
    SELECT 
      CONCAT(first, '_', last) as customer_id,
      trans_date_trans_time,
      amt,
      merchant,
      DATE(trans_date_trans_time) as transaction_date
    FROM `anlaytics-465216.aml_data.credit_card_transactions`
    WHERE trans_date_trans_time > last_processed_time
  ),
  
  -- Get recent transactions for velocity analysis (include some history)
  velocity_data AS (
    SELECT 
      CONCAT(first, '_', last) as customer_id,
      trans_date_trans_time,
      amt,
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
    WHERE trans_date_trans_time > TIMESTAMP_SUB(last_processed_time, INTERVAL 1 DAY)
  ),
  
  rapid_transactions AS (
    SELECT 
      customer_id,
      transaction_date,
      COUNT(*) as rapid_transaction_count,
      SUM(amt) as total_amount,
      MIN(minutes_since_last) as min_time_diff
    FROM velocity_data
    WHERE minutes_since_last <= 5 
      AND transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    GROUP BY customer_id, transaction_date
    HAVING COUNT(*) >= 5
  )
  
  SELECT 
    (SELECT IFNULL(MAX(alert_id), 0) FROM `anlaytics-465216.aml_data.aml_alerts_level1`) + 
    ROW_NUMBER() OVER (ORDER BY rapid_transaction_count DESC) as alert_id,
    customer_id,
    transaction_date as alert_date,
    'VELOCITY' as alert_type,
    LEAST(rapid_transaction_count * 20, 100) as risk_score,
    CONCAT(
      'Customer made ', rapid_transaction_count, 
      ' rapid transactions (≤5 mins) totaling $', 
      FORMAT('%\'.0f', total_amount)
    ) as description,
    CASE 
      WHEN rapid_transaction_count * 20 >= 80 THEN 'HIGH'
      WHEN rapid_transaction_count * 20 >= 50 THEN 'MEDIUM'
      ELSE 'LOW'
    END as priority,
    total_amount,
    'OPEN' as status,
    CURRENT_DATE() as detection_date,
    CURRENT_TIMESTAMP() as created_at
  FROM rapid_transactions;
  
  -- ===========================================
  -- 2. STRUCTURING DETECTION
  -- ===========================================
  INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
  WITH structuring_analysis AS (
    SELECT 
      CONCAT(first, '_', last) as customer_id,
      DATE(trans_date_trans_time) as transaction_date,
      COUNT(*) as transaction_count,
      SUM(amt) as total_amount,
      AVG(amt) as avg_amount
    FROM `anlaytics-465216.aml_data.credit_card_transactions`
    WHERE trans_date_trans_time > last_processed_time
      AND amt BETWEEN 9000 AND 9999  -- Just under $10K threshold
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
    CURRENT_DATE() as detection_date,
    CURRENT_TIMESTAMP() as created_at
  FROM structuring_analysis;
  
  -- ===========================================
  -- 3. GEOGRAPHIC ANOMALY DETECTION
  -- ===========================================
  INSERT INTO `anlaytics-465216.aml_data.aml_alerts_level1`
  WITH geographic_analysis AS (
    SELECT 
      CONCAT(first, '_', last) as customer_id,
      DATE(trans_date_trans_time) as transaction_date,
      COUNT(DISTINCT state) as unique_states,
      COUNT(DISTINCT city) as unique_cities,
      COUNT(*) as transaction_count,
      SUM(amt) as total_amount,
      STRING_AGG(DISTINCT state, ', ') as states_list
    FROM `anlaytics-465216.aml_data.credit_card_transactions`
    WHERE trans_date_trans_time > last_processed_time
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
    CURRENT_DATE() as detection_date,
    CURRENT_TIMESTAMP() as created_at
  FROM geographic_analysis;
  
  -- ===========================================
  -- 4. UPDATE CUSTOMER RISK PROFILES
  -- ===========================================
  CREATE OR REPLACE TABLE `anlaytics-465216.aml_data.customer_risk_profiles_level2` AS
  WITH customer_metrics AS (
    SELECT 
      CONCAT(first, '_', last) as customer_id,
      COUNT(*) as total_transactions,
      SUM(amt) as total_amount,
      AVG(amt) as avg_amount,
      MAX(amt) as max_amount,
      COUNT(DISTINCT merchant) as unique_merchants,
      COUNT(DISTINCT state) as unique_states,
      SUM(CASE WHEN amt > 5000 THEN 1 ELSE 0 END) as high_amount_transactions,
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
      MAX(risk_score) as max_alert_risk_score
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
    
    -- Calculate risk score
    LEAST(
      (IFNULL(a.total_alerts, 0) * 20) +
      (m.high_amount_transactions * 5) +
      (m.unique_states * 10),
      100
    ) as risk_score,
    
    -- Assign risk category
    CASE 
      WHEN LEAST(
        (IFNULL(a.total_alerts, 0) * 20) +
        (m.high_amount_transactions * 5) +
        (m.unique_states * 10),
        100
      ) >= 80 THEN 'CRITICAL'
      WHEN LEAST(
        (IFNULL(a.total_alerts, 0) * 20) +
        (m.high_amount_transactions * 5) +
        (m.unique_states * 10),
        100
      ) >= 60 THEN 'HIGH'
      WHEN LEAST(
        (IFNULL(a.total_alerts, 0) * 20) +
        (m.high_amount_transactions * 5) +
        (m.unique_states * 10),
        100
      ) >= 40 THEN 'MEDIUM'
      ELSE 'LOW'
    END as risk_category,
    
    IFNULL(a.total_alerts, 0) as total_alerts,
    IFNULL(a.high_priority_alerts, 0) as high_priority_alerts,
    IFNULL(a.max_alert_risk_score, 0) as max_alert_risk_score,
    m.first_transaction_date,
    m.last_transaction_date,
    CURRENT_TIMESTAMP() as profile_generated_date
  FROM customer_metrics m
  LEFT JOIN customer_alerts a ON m.customer_id = a.customer_id
  ORDER BY risk_score DESC;
  
  -- ===========================================
  -- 5. UPDATE PROCESSING METADATA
  -- ===========================================
  SET alerts_created = (
    SELECT COUNT(*)
    FROM `anlaytics-465216.aml_data.aml_alerts_level1`
    WHERE created_at >= processing_start_time
  );
  
  UPDATE `anlaytics-465216.aml_data.processing_metadata`
  SET 
    last_processed_timestamp = (
      SELECT MAX(trans_date_trans_time)
      FROM `anlaytics-465216.aml_data.credit_card_transactions`
    ),
    total_records_processed = total_records_processed + new_records_count,
    last_run_date = CURRENT_DATE(),
    alerts_generated = alerts_generated + alerts_created,
    processing_duration_seconds = TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), processing_start_time, SECOND),
    status = 'COMPLETED',
    updated_at = CURRENT_TIMESTAMP()
  WHERE process_name = 'aml_processing';
  
  -- ===========================================
  -- 6. PROCESSING SUMMARY
  -- ===========================================
  SELECT 
    CONCAT('Processed ', new_records_count, ' new transactions') as processing_summary,
    CONCAT('Generated ', alerts_created, ' new alerts') as alerts_summary,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), processing_start_time, SECOND) as processing_time_seconds,
    CURRENT_TIMESTAMP() as completed_at;
    
END IF;