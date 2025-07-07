-- ============================================================================
-- SETUP BIGQUERY SCHEDULED QUERY
-- Creates a scheduled query to run AML processing every 30 minutes
-- ============================================================================

-- Note: This SQL shows the structure. Actual scheduled query must be created 
-- through BigQuery Console or gcloud command due to syntax limitations.

/*
To create the scheduled query, run this gcloud command:

gcloud scheduler jobs create bigquery aml-processing-scheduler \
    --schedule="*/30 * * * *" \
    --location=us-central1 \
    --max-retry-attempts=3 \
    --max-retry-duration=3600s \
    --time-zone="America/New_York" \
    --description="AML Processing - Runs every 30 minutes to detect new alerts" \
    --query-file=sql/incremental_aml_processing.sql \
    --use-legacy-sql=false \
    --project=anlaytics-465216

OR use BigQuery Console:
1. Go to BigQuery Console
2. Click "Scheduled queries"
3. Click "Create scheduled query"
4. Paste the incremental_aml_processing.sql content
5. Set schedule: "*/30 * * * *" (every 30 minutes)
6. Set timezone: America/New_York
7. Save as "AML-Processing-Scheduler"

*/

-- Verify scheduled query is working by checking metadata
SELECT 
  process_name,
  last_processed_timestamp,
  total_records_processed,
  last_run_date,
  alerts_generated,
  processing_duration_seconds,
  status,
  updated_at
FROM `anlaytics-465216.aml_data.processing_metadata`
WHERE process_name = 'aml_processing'
ORDER BY updated_at DESC;