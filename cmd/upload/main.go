package main

import (
	"bufio"
	"context"
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/bigquery"
	"github.com/fatih/color"
	"google.golang.org/api/iterator"
)

// Configuration
const (
	ProjectID = "anlaytics-465216"
	DatasetID = "aml_data"
	TableName = "credit_card_transactions"
	Location  = "US"
)

// Color functions for output
var (
	info    = color.New(color.FgBlue).Add(color.Bold)
	success = color.New(color.FgGreen).Add(color.Bold)
	warning = color.New(color.FgYellow).Add(color.Bold)
	errorC  = color.New(color.FgRed).Add(color.Bold)
	process = color.New(color.FgMagenta).Add(color.Bold)
)

type AMLUploader struct {
	client   *bigquery.Client
	ctx      context.Context
	dataset  *bigquery.Dataset
	table    *bigquery.Table
	startTime time.Time
}

// TransactionRow represents a transaction record
type TransactionRow struct {
	TransDateTransTime time.Time `bigquery:"trans_date_trans_time"`
	CCNum              int64     `bigquery:"cc_num"`
	Merchant           string    `bigquery:"merchant"`
	Category           string    `bigquery:"category"`
	Amount             float64   `bigquery:"amt"`
	First              string    `bigquery:"first"`
	Last               string    `bigquery:"last"`
	Gender             string    `bigquery:"gender"`
	Street             string    `bigquery:"street"`
	City               string    `bigquery:"city"`
	State              string    `bigquery:"state"`
	Zip                string    `bigquery:"zip"`
	Lat                float64   `bigquery:"lat"`
	Long               float64   `bigquery:"long"`
	CityPop            int64     `bigquery:"city_pop"`
	Job                string    `bigquery:"job"`
	DOB                string    `bigquery:"dob"`
	TransNum           string    `bigquery:"trans_num"`
	UnixTime           int64     `bigquery:"unix_time"`
	MerchLat           float64   `bigquery:"merch_lat"`
	MerchLong          float64   `bigquery:"merch_long"`
	IsFraud            bool      `bigquery:"is_fraud"`
}

func NewAMLUploader() (*AMLUploader, error) {
	ctx := context.Background()
	
	client, err := bigquery.NewClient(ctx, ProjectID)
	if err != nil {
		return nil, fmt.Errorf("failed to create BigQuery client: %v", err)
	}

	uploader := &AMLUploader{
		client:    client,
		ctx:       ctx,
		dataset:   client.Dataset(DatasetID),
		startTime: time.Now(),
	}

	uploader.table = uploader.dataset.Table(TableName)
	
	return uploader, nil
}

func (u *AMLUploader) Close() error {
	return u.client.Close()
}

func (u *AMLUploader) printStatus(message string) {
	info.Printf("[INFO] %s\n", message)
}

func (u *AMLUploader) printSuccess(message string) {
	success.Printf("[SUCCESS] %s\n", message)
}

func (u *AMLUploader) printWarning(message string) {
	warning.Printf("[WARNING] %s\n", message)
}

func (u *AMLUploader) printError(message string) {
	errorC.Printf("[ERROR] %s\n", message)
}

func (u *AMLUploader) printProcessing(message string) {
	process.Printf("[PROCESSING] %s\n", message)
}

func (u *AMLUploader) checkFile(csvFile string) (float64, int, error) {
	// Check if file exists
	if _, err := os.Stat(csvFile); os.IsNotExist(err) {
		return 0, 0, fmt.Errorf("file not found: %s", csvFile)
	}

	// Get file size
	fileInfo, err := os.Stat(csvFile)
	if err != nil {
		return 0, 0, err
	}
	fileSizeMB := float64(fileInfo.Size()) / (1024 * 1024)

	// Count rows
	file, err := os.Open(csvFile)
	if err != nil {
		return fileSizeMB, 0, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	rowCount := 0
	for scanner.Scan() {
		rowCount++
	}
	rowCount-- // Subtract header

	return fileSizeMB, rowCount, nil
}

func (u *AMLUploader) ensureDatasetExists() error {
	// Check if dataset exists
	_, err := u.dataset.Metadata(u.ctx)
	if err != nil {
		u.printWarning(fmt.Sprintf("Dataset %s not found. Creating...", DatasetID))
		
		// Create dataset
		meta := &bigquery.DatasetMetadata{
			Location: Location,
		}
		
		if err := u.dataset.Create(u.ctx, meta); err != nil {
			return fmt.Errorf("failed to create dataset: %v", err)
		}
		
		u.printSuccess("Dataset created successfully")
	} else {
		u.printStatus(fmt.Sprintf("Dataset %s exists", DatasetID))
	}
	
	return nil
}

func (u *AMLUploader) getCurrentTableInfo() (int64, error) {
	query := fmt.Sprintf("SELECT COUNT(*) as count FROM `%s.%s.%s`", ProjectID, DatasetID, TableName)
	
	q := u.client.Query(query)
	it, err := q.Read(u.ctx)
	if err != nil {
		return 0, nil // Table might not exist yet
	}

	var row []bigquery.Value
	err = it.Next(&row)
	if err != nil {
		return 0, nil
	}

	count, ok := row[0].(int64)
	if !ok {
		return 0, nil
	}

	return count, nil
}

func (u *AMLUploader) uploadCSVToBigQuery(csvFile string) error {
	u.printProcessing("Uploading CSV to BigQuery...")
	u.printWarning("This will REPLACE all existing data in the table")

	// Open CSV file
	file, err := os.Open(csvFile)
	if err != nil {
		return fmt.Errorf("failed to open CSV file: %v", err)
	}
	defer file.Close()

	// Create table reference
	tableRef := u.dataset.Table(TableName)

	// Configure the load job
	loader := tableRef.LoaderFrom(bigquery.NewReaderSource(file))
	loader.SourceFormat = bigquery.CSV
	loader.SkipLeadingRows = 1 // Skip header
	loader.AutoDetect = true
	loader.WriteDisposition = bigquery.WriteTruncate // Replace existing data

	// Start the job
	job, err := loader.Run(u.ctx)
	if err != nil {
		return fmt.Errorf("failed to start load job: %v", err)
	}

	// Wait for completion
	status, err := job.Wait(u.ctx)
	if err != nil {
		return fmt.Errorf("job failed: %v", err)
	}

	if status.Err() != nil {
		return fmt.Errorf("job completed with error: %v", status.Err())
	}

	u.printSuccess("CSV uploaded successfully!")
	return nil
}

func (u *AMLUploader) verifyUpload() (int64, error) {
	u.printProcessing("Verifying upload...")

	// Get row count
	query := fmt.Sprintf("SELECT COUNT(*) as count FROM `%s.%s.%s`", ProjectID, DatasetID, TableName)
	q := u.client.Query(query)
	it, err := q.Read(u.ctx)
	if err != nil {
		return 0, fmt.Errorf("failed to get row count: %v", err)
	}

	var row []bigquery.Value
	err = it.Next(&row)
	if err != nil {
		return 0, fmt.Errorf("failed to read row count: %v", err)
	}

	newRows, ok := row[0].(int64)
	if !ok {
		return 0, fmt.Errorf("unexpected row count type")
	}

	u.printSuccess(fmt.Sprintf("Table now has %s rows", formatNumber(newRows)))

	// Show sample data
	sampleQuery := fmt.Sprintf(`
		SELECT trans_date_trans_time, merchant, category, amt, first, last 
		FROM %s.%s.%s 
		ORDER BY trans_date_trans_time DESC 
		LIMIT 3
	`, ProjectID, DatasetID, TableName)

	u.printStatus("Sample of uploaded data:")
	q = u.client.Query(sampleQuery)
	it, err = q.Read(u.ctx)
	if err == nil {
		for {
			var values []bigquery.Value
			err := it.Next(&values)
			if err == iterator.Done {
				break
			}
			if err != nil {
				break
			}
			fmt.Printf("  %v | %v | $%.2f | %v %v\n", 
				values[0], values[1], values[3], values[4], values[5])
		}
	}

	// Check recent transactions
	recentQuery := fmt.Sprintf(`
		SELECT COUNT(*) as count 
		FROM %s.%s.%s 
		WHERE DATE(trans_date_trans_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7)
	`, ProjectID, DatasetID, TableName)

	q = u.client.Query(recentQuery)
	it, err = q.Read(u.ctx)
	if err == nil {
		var row []bigquery.Value
		if it.Next(&row) == nil {
			if recentCount, ok := row[0].(int64); ok {
				u.printStatus(fmt.Sprintf("Transactions from last 7 days: %s", formatNumber(recentCount)))
			}
		}
	}

	return newRows, nil
}

func (u *AMLUploader) triggerAMLProcessing() error {
	u.printProcessing("🚀 Triggering AML processing...")

	// Read SQL file
	sqlFile := "sql/incremental_aml_processing.sql"
	sqlContent, err := os.ReadFile(sqlFile)
	if err != nil {
		return fmt.Errorf("failed to read SQL file %s: %v", sqlFile, err)
	}

	u.printStatus("Running AML detection algorithms...")

	// Execute the processing SQL
	q := u.client.Query(string(sqlContent))
	job, err := q.Run(u.ctx)
	if err != nil {
		return fmt.Errorf("failed to start AML processing job: %v", err)
	}

	// Wait for completion
	status, err := job.Wait(u.ctx)
	if err != nil {
		return fmt.Errorf("AML processing job failed: %v", err)
	}

	if status.Err() != nil {
		return fmt.Errorf("AML processing completed with error: %v", status.Err())
	}

	u.printSuccess("AML processing completed successfully!")
	return nil
}

func (u *AMLUploader) checkProcessingStatus() {
	query := fmt.Sprintf(`
		SELECT 
			last_processed_timestamp,
			total_records_processed,
			alerts_generated,
			status,
			updated_at
		FROM %s.%s.processing_metadata
		WHERE process_name = 'aml_processing'
	`, ProjectID, DatasetID)

	q := u.client.Query(query)
	it, err := q.Read(u.ctx)
	if err != nil {
		u.printWarning("Could not retrieve processing status")
		return
	}

	var row []bigquery.Value
	if it.Next(&row) == nil {
		u.printStatus(fmt.Sprintf("Last processed: %v", row[0]))
		if totalProcessed, ok := row[1].(int64); ok {
			u.printStatus(fmt.Sprintf("Total records processed: %s", formatNumber(totalProcessed)))
		}
		if alertsGenerated, ok := row[2].(int64); ok {
			u.printStatus(fmt.Sprintf("Alerts generated: %s", formatNumber(alertsGenerated)))
		}
		u.printStatus(fmt.Sprintf("Status: %v", row[3]))
	}
}

func formatNumber(n int64) string {
	str := strconv.FormatInt(n, 10)
	if len(str) <= 3 {
		return str
	}
	
	result := ""
	for i, char := range str {
		if i > 0 && (len(str)-i)%3 == 0 {
			result += ","
		}
		result += string(char)
	}
	return result
}

func main() {
	info.Println("🏦 AML Data Upload and Processing System")
	info.Println(strings.Repeat("=", 50))

	// Get CSV file path
	var csvFile string
	if len(os.Args) < 2 {
		csvFile = "credit_card_transactions.csv"
		warning.Printf("No CSV file specified. Using default: %s\n", csvFile)
	} else {
		csvFile = os.Args[1]
	}

	// Initialize uploader
	uploader, err := NewAMLUploader()
	if err != nil {
		log.Fatalf("Failed to initialize AML uploader: %v", err)
	}
	defer uploader.Close()

	// Check file
	fileSizeMB, rowCount, err := uploader.checkFile(csvFile)
	if err != nil {
		uploader.printError(err.Error())
		fmt.Println("Usage: go run cmd/upload/main.go [csv_file_path]")
		os.Exit(1)
	}
	uploader.printStatus(fmt.Sprintf("File: %s (%.1f MB, ~%s records)", 
		csvFile, fileSizeMB, formatNumber(int64(rowCount))))

	// Ensure dataset exists
	if err := uploader.ensureDatasetExists(); err != nil {
		log.Fatalf("Failed to ensure dataset exists: %v", err)
	}

	// Get current table info
	currentRows, _ := uploader.getCurrentTableInfo()
	uploader.printStatus(fmt.Sprintf("Current table has %s rows", formatNumber(currentRows)))

	startTime := time.Now()

	// Upload CSV
	if err := uploader.uploadCSVToBigQuery(csvFile); err != nil {
		uploader.printError(fmt.Sprintf("Upload failed: %v", err))
		os.Exit(1)
	}

	// Verify upload
	newRows, err := uploader.verifyUpload()
	if err != nil {
		uploader.printError(fmt.Sprintf("Verification failed: %v", err))
		os.Exit(1)
	}

	if newRows > 0 {
		uploadTime := time.Since(startTime)
		uploader.printSuccess(fmt.Sprintf("Upload completed in %.1f seconds", uploadTime.Seconds()))

		// Trigger immediate processing
		processingStart := time.Now()
		if err := uploader.triggerAMLProcessing(); err != nil {
			uploader.printError(fmt.Sprintf("AML processing failed: %v", err))
		} else {
			processingTime := time.Since(processingStart)
			uploader.printSuccess(fmt.Sprintf("AML processing completed in %.1f seconds", processingTime.Seconds()))

			// Show final status
			uploader.printStatus("\n📊 Final Status:")
			uploader.checkProcessingStatus()

			totalTime := time.Since(startTime)
			uploader.printSuccess(fmt.Sprintf("\n🎉 Complete pipeline finished in %.1f seconds!", totalTime.Seconds()))
			uploader.printStatus("📋 Summary:")
			fmt.Printf("   • File uploaded: %s (%.1f MB)\n", csvFile, fileSizeMB)
			fmt.Printf("   • Records processed: %s\n", formatNumber(newRows))
			fmt.Printf("   • Processing: IMMEDIATE (no waiting)\n")
			uploader.printStatus("\n📊 Dashboard will show updated alerts immediately!")
		}
	} else {
		uploader.printError("Upload verification failed")
		os.Exit(1)
	}
}