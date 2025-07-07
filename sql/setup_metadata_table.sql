-- ============================================================================
-- METADATA TABLE SETUP - Track processing timestamps
-- Creates table to monitor last processed data
-- ============================================================================

-- Create metadata table for tracking processing state
CREATE TABLE IF NOT EXISTS `anlaytics-465216.aml_data.processing_metadata` (
  process_name STRING NOT NULL,
  last_processed_timestamp TIMESTAMP,
  total_records_processed INT64,
  last_run_date DATE,
  alerts_generated INT64,
  processing_duration_seconds FLOAT64,
  status STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Initialize metadata for AML processing
MERGE `anlaytics-465216.aml_data.processing_metadata` AS target
USING (
  SELECT 
    'aml_processing' as process_name,
    TIMESTAMP('2020-01-01 00:00:00') as last_processed_timestamp,
    0 as total_records_processed,
    DATE('2020-01-01') as last_run_date,
    0 as alerts_generated,
    0.0 as processing_duration_seconds,
    'INITIALIZED' as status
) AS source
ON target.process_name = source.process_name
WHEN NOT MATCHED THEN
  INSERT (
    process_name, 
    last_processed_timestamp, 
    total_records_processed,
    last_run_date,
    alerts_generated,
    processing_duration_seconds,
    status
  )
  VALUES (
    source.process_name,
    source.last_processed_timestamp,
    source.total_records_processed,
    source.last_run_date,
    source.alerts_generated,
    source.processing_duration_seconds,
    source.status
  );

-- Create alerts table if not exists
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
  detection_date DATE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Create customer risk profiles table if not exists
CREATE TABLE IF NOT EXISTS `anlaytics-465216.aml_data.customer_risk_profiles_level2` (
  customer_id STRING,
  total_transactions INT64,
  total_amount FLOAT64,
  avg_amount FLOAT64,
  max_amount FLOAT64,
  unique_merchants INT64,
  unique_states INT64,
  risk_score INT64,
  risk_category STRING,
  total_alerts INT64,
  high_priority_alerts INT64,
  max_alert_risk_score INT64,
  first_transaction_date DATE,
  last_transaction_date DATE,
  profile_generated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Show current metadata state
SELECT 
  process_name,
  last_processed_timestamp,
  total_records_processed,
  last_run_date,
  alerts_generated,
  status,
  updated_at
FROM `anlaytics-465216.aml_data.processing_metadata`;