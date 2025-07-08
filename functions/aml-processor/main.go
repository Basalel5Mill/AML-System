package amlprocessor

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"time"

	"cloud.google.com/go/bigquery"
	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
)

// BigQueryEvent represents a Cloud Pub/Sub message payload for BigQuery events
type BigQueryEvent struct {
	Data []byte `json:"data"`
}

// BigQueryData represents the data payload from BigQuery
type BigQueryData struct {
	InsertId      string    `json:"insertId"`
	TableId       string    `json:"tableId"`
	DatasetId     string    `json:"datasetId"`
	ProjectId     string    `json:"projectId"`
	EventTime     time.Time `json:"eventTime"`
	EventType     string    `json:"eventType"`
	NumRowsInserted int64   `json:"numRowsInserted"`
}

const (
	ProjectID = "anlaytics-465216"
	DatasetID = "aml_data"
	TableName = "credit_card_transactions"
)

func init() {
	functions.CloudEvent("ProcessAMLAlerts", ProcessAMLAlerts)
}

// ProcessAMLAlerts processes new BigQuery data and runs AML detection
func ProcessAMLAlerts(ctx context.Context, e BigQueryEvent) error {
	log.Printf("🚀 AML Cloud Function triggered")

	// Parse the event data
	var bqData BigQueryData
	if err := json.Unmarshal(e.Data, &bqData); err != nil {
		log.Printf("❌ Failed to parse event data: %v", err)
		return err
	}

	log.Printf("📊 BigQuery Event: %s.%s.%s - %d rows added", 
		bqData.ProjectId, bqData.DatasetId, bqData.TableId, bqData.NumRowsInserted)

	// Only process events for our transaction table
	if bqData.TableId != TableName || bqData.DatasetId != DatasetID {
		log.Printf("⏭️  Skipping - not our target table")
		return nil
	}

	// Skip if no new rows
	if bqData.NumRowsInserted == 0 {
		log.Printf("⏭️  Skipping - no new rows added")
		return nil
	}

	// Initialize BigQuery client
	client, err := bigquery.NewClient(ctx, ProjectID)
	if err != nil {
		log.Printf("❌ Failed to create BigQuery client: %v", err)
		return err
	}
	defer client.Close()

	// Run AML processing
	if err := runAMLProcessing(ctx, client); err != nil {
		log.Printf("❌ AML processing failed: %v", err)
		return err
	}

	log.Printf("✅ AML processing completed successfully")
	return nil
}

func runAMLProcessing(ctx context.Context, client *bigquery.Client) error {
	log.Printf("🔍 Running AML detection algorithms...")

	// Read the SQL file - in Cloud Functions, we need to embed or store SQL
	sqlQuery := getAMLProcessingSQL()

	// Execute the processing SQL
	q := client.Query(sqlQuery)
	job, err := q.Run(ctx)
	if err != nil {
		return fmt.Errorf("failed to start AML processing job: %v", err)
	}

	// Wait for completion
	status, err := job.Wait(ctx)
	if err != nil {
		return fmt.Errorf("AML processing job failed: %v", err)
	}

	if status.Err() != nil {
		return fmt.Errorf("AML processing completed with error: %v", status.Err())
	}

	// Log processing results
	logProcessingResults(ctx, client)

	return nil
}

func getAMLProcessingSQL() string {
	// Embedded SQL for AML processing
	// In production, you might load this from Cloud Storage or embed it
	return `
-- Update processing metadata
MERGE ` + "`anlaytics-465216.aml_data.processing_metadata`" + ` AS target
USING (
  SELECT 
    'aml_processing' as process_name,
    CURRENT_TIMESTAMP() as processing_start_time,
    (
      SELECT COUNT(*) 
      FROM ` + "`anlaytics-465216.aml_data.credit_card_transactions`" + `
      WHERE trans_date_trans_time > COALESCE(
        (SELECT last_processed_timestamp FROM ` + "`anlaytics-465216.aml_data.processing_metadata`" + ` WHERE process_name = 'aml_processing'),
        TIMESTAMP('2020-01-01 00:00:00')
      )
    ) as new_records_count
) AS source
ON target.process_name = source.process_name
WHEN MATCHED THEN
  UPDATE SET
    last_processed_timestamp = CURRENT_TIMESTAMP(),
    total_records_processed = target.total_records_processed + source.new_records_count,
    last_run_date = CURRENT_DATE(),
    status = 'PROCESSING',
    updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
  INSERT (
    process_name,
    last_processed_timestamp,
    total_records_processed,
    last_run_date,
    status,
    updated_at
  )
  VALUES (
    source.process_name,
    source.processing_start_time,
    source.new_records_count,
    CURRENT_DATE(),
    'PROCESSING',
    CURRENT_TIMESTAMP()
  );

-- Insert velocity alerts for rapid transactions
INSERT INTO ` + "`anlaytics-465216.aml_data.aml_alerts_level1`" + `
WITH velocity_data AS (
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
  FROM ` + "`anlaytics-465216.aml_data.credit_card_transactions`" + `
  WHERE trans_date_trans_time > COALESCE(
    (SELECT last_processed_timestamp FROM ` + "`anlaytics-465216.aml_data.processing_metadata`" + ` WHERE process_name = 'aml_processing'),
    TIMESTAMP('2020-01-01 00:00:00')
  )
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
  (SELECT IFNULL(MAX(alert_id), 0) FROM ` + "`anlaytics-465216.aml_data.aml_alerts_level1`" + `) + 
  ROW_NUMBER() OVER (ORDER BY rapid_transaction_count DESC) as alert_id,
  customer_id,
  transaction_date as alert_date,
  'VELOCITY' as alert_type,
  LEAST(GREATEST(rapid_transaction_count * 15, 60), 100) as risk_score,
  CONCAT('Rapid transactions detected: ', rapid_transaction_count, ' transactions within 5 minutes') as description,
  CASE 
    WHEN rapid_transaction_count >= 10 THEN 'HIGH'
    WHEN rapid_transaction_count >= 7 THEN 'MEDIUM'
    ELSE 'LOW'
  END as priority,
  total_amount,
  'OPEN' as status,
  CURRENT_DATE() as detection_date,
  CURRENT_TIMESTAMP() as created_at
FROM rapid_transactions;

-- Update final processing status
UPDATE ` + "`anlaytics-465216.aml_data.processing_metadata`" + `
SET 
  alerts_generated = (
    SELECT COUNT(*) 
    FROM ` + "`anlaytics-465216.aml_data.aml_alerts_level1`" + `
    WHERE DATE(created_at) = CURRENT_DATE()
  ),
  status = 'COMPLETED',
  processing_duration_seconds = TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), updated_at, SECOND),
  updated_at = CURRENT_TIMESTAMP()
WHERE process_name = 'aml_processing';
`
}

func logProcessingResults(ctx context.Context, client *bigquery.Client) {
	query := fmt.Sprintf(`
		SELECT 
			total_records_processed,
			alerts_generated,
			processing_duration_seconds,
			status,
			updated_at
		FROM %s.%s.processing_metadata
		WHERE process_name = 'aml_processing'
	`, ProjectID, DatasetID)

	q := client.Query(query)
	it, err := q.Read(ctx)
	if err != nil {
		log.Printf("⚠️  Could not retrieve processing status: %v", err)
		return
	}

	var row []bigquery.Value
	if it.Next(&row) == nil {
		log.Printf("📊 Processing Results:")
		log.Printf("   • Records processed: %v", row[0])
		log.Printf("   • Alerts generated: %v", row[1])
		log.Printf("   • Duration: %v seconds", row[2])
		log.Printf("   • Status: %v", row[3])
		log.Printf("   • Completed: %v", row[4])
	}
}