package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cloud.google.com/go/bigquery"
	"github.com/fatih/color"
	"google.golang.org/api/iterator"
)

// Configuration
const (
	ProjectID      = "anlaytics-465216"
	DatasetID      = "aml_data"
	TableName      = "credit_card_transactions"
	MonitorInterval = 30 * time.Second // Check every 30 seconds
)

// Color functions
var (
	info    = color.New(color.FgBlue).Add(color.Bold)
	success = color.New(color.FgGreen).Add(color.Bold)
	warning = color.New(color.FgYellow).Add(color.Bold)
	errorC  = color.New(color.FgRed).Add(color.Bold)
	monitor = color.New(color.FgCyan).Add(color.Bold)
)

type AMLMonitor struct {
	client        *bigquery.Client
	ctx           context.Context
	lastRowCount  int64
	lastProcessed time.Time
	running       bool
}

func NewAMLMonitor() (*AMLMonitor, error) {
	ctx := context.Background()
	
	client, err := bigquery.NewClient(ctx, ProjectID)
	if err != nil {
		return nil, fmt.Errorf("failed to create BigQuery client: %v", err)
	}

	return &AMLMonitor{
		client:  client,
		ctx:     ctx,
		running: true,
	}, nil
}

func (m *AMLMonitor) Close() error {
	return m.client.Close()
}

func (m *AMLMonitor) printMonitor(message string) {
	monitor.Printf("[MONITOR] %s\n", message)
}

func (m *AMLMonitor) printInfo(message string) {
	info.Printf("[INFO] %s\n", message)
}

func (m *AMLMonitor) printSuccess(message string) {
	success.Printf("[SUCCESS] %s\n", message)
}

func (m *AMLMonitor) printWarning(message string) {
	warning.Printf("[WARNING] %s\n", message)
}

func (m *AMLMonitor) printError(message string) {
	errorC.Printf("[ERROR] %s\n", message)
}

func (m *AMLMonitor) getCurrentRowCount() (int64, error) {
	query := fmt.Sprintf("SELECT COUNT(*) as count FROM `%s.%s.%s`", ProjectID, DatasetID, TableName)
	
	q := m.client.Query(query)
	it, err := q.Read(m.ctx)
	if err != nil {
		return 0, err
	}

	var row []bigquery.Value
	err = it.Next(&row)
	if err != nil {
		return 0, err
	}

	count, ok := row[0].(int64)
	if !ok {
		return 0, fmt.Errorf("unexpected count type")
	}

	return count, nil
}

func (m *AMLMonitor) getLastProcessedTime() (time.Time, error) {
	query := fmt.Sprintf(`
		SELECT last_processed_timestamp
		FROM %s.%s.processing_metadata
		WHERE process_name = 'aml_processing'
	`, ProjectID, DatasetID)

	q := m.client.Query(query)
	it, err := q.Read(m.ctx)
	if err != nil {
		return time.Time{}, err
	}

	var row []bigquery.Value
	err = it.Next(&row)
	if err != nil {
		return time.Time{}, err
	}

	if row[0] == nil {
		return time.Time{}, nil
	}

	timestamp, ok := row[0].(time.Time)
	if !ok {
		return time.Time{}, fmt.Errorf("unexpected timestamp type")
	}

	return timestamp, nil
}

func (m *AMLMonitor) triggerAMLProcessing() error {
	m.printMonitor("🚀 Triggering AML processing due to new data...")

	// Read SQL file
	sqlFile := "sql/incremental_aml_processing.sql"
	sqlContent, err := os.ReadFile(sqlFile)
	if err != nil {
		return fmt.Errorf("failed to read SQL file %s: %v", sqlFile, err)
	}

	// Execute the processing SQL
	q := m.client.Query(string(sqlContent))
	job, err := q.Run(m.ctx)
	if err != nil {
		return fmt.Errorf("failed to start AML processing job: %v", err)
	}

	// Wait for completion
	status, err := job.Wait(m.ctx)
	if err != nil {
		return fmt.Errorf("AML processing job failed: %v", err)
	}

	if status.Err() != nil {
		return fmt.Errorf("AML processing completed with error: %v", status.Err())
	}

	m.printSuccess("AML processing completed successfully!")
	return nil
}

func (m *AMLMonitor) checkForNewData() error {
	// Get current row count
	currentRows, err := m.getCurrentRowCount()
	if err != nil {
		return fmt.Errorf("failed to get current row count: %v", err)
	}

	// Get last processed timestamp
	lastProcessed, err := m.getLastProcessedTime()
	if err != nil {
		m.printWarning("Could not get last processed time, assuming first run")
		lastProcessed = time.Time{}
	}

	// Check if we have new data since last processing
	if m.lastRowCount == 0 {
		// First run - just store current state
		m.lastRowCount = currentRows
		m.lastProcessed = lastProcessed
		m.printInfo(fmt.Sprintf("Initial state: %d rows, last processed: %v", currentRows, lastProcessed))
		return nil
	}

	// Check for row count changes
	if currentRows > m.lastRowCount {
		newRows := currentRows - m.lastRowCount
		m.printMonitor(fmt.Sprintf("🔔 New data detected! %d new rows (total: %d)", newRows, currentRows))
		
		// Trigger processing
		if err := m.triggerAMLProcessing(); err != nil {
			m.printError(fmt.Sprintf("Failed to trigger AML processing: %v", err))
		} else {
			m.lastRowCount = currentRows
			m.printSuccess("✅ Processing completed for new data")
		}
	} else if currentRows < m.lastRowCount {
		// Data was replaced/truncated
		m.printMonitor(fmt.Sprintf("🔄 Data replaced detected! New count: %d (was: %d)", currentRows, m.lastRowCount))
		
		// Trigger processing for replaced data
		if err := m.triggerAMLProcessing(); err != nil {
			m.printError(fmt.Sprintf("Failed to trigger AML processing: %v", err))
		} else {
			m.lastRowCount = currentRows
			m.printSuccess("✅ Processing completed for replaced data")
		}
	} else {
		// No change
		m.printInfo(fmt.Sprintf("No new data (current: %d rows)", currentRows))
	}

	return nil
}

func (m *AMLMonitor) getAlertsSummary() {
	query := fmt.Sprintf(`
		SELECT 
			alert_type,
			priority,
			COUNT(*) as count
		FROM %s.%s.aml_alerts_level1
		WHERE DATE(created_at) = CURRENT_DATE()
		GROUP BY alert_type, priority
		ORDER BY alert_type, priority
	`, ProjectID, DatasetID)

	q := m.client.Query(query)
	it, err := q.Read(m.ctx)
	if err != nil {
		return
	}

	m.printInfo("📊 Today's Alert Summary:")
	alertCount := 0
	for {
		var row []bigquery.Value
		err := it.Next(&row)
		if err == iterator.Done {
			break
		}
		if err != nil {
			break
		}
		
		alertType := row[0].(string)
		priority := row[1].(string)
		count := row[2].(int64)
		alertCount += int(count)
		
		fmt.Printf("   • %s (%s): %d alerts\n", alertType, priority, count)
	}
	
	if alertCount == 0 {
		m.printInfo("   • No alerts generated today")
	}
}

func (m *AMLMonitor) start() {
	m.printMonitor("🔍 Starting AML Real-Time Monitor")
	m.printInfo(fmt.Sprintf("Monitoring table: %s.%s.%s", ProjectID, DatasetID, TableName))
	m.printInfo(fmt.Sprintf("Check interval: %v", MonitorInterval))
	fmt.Println()

	ticker := time.NewTicker(MonitorInterval)
	defer ticker.Stop()

	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Initial check
	if err := m.checkForNewData(); err != nil {
		m.printError(fmt.Sprintf("Initial check failed: %v", err))
	}

	// Show initial alert summary
	m.getAlertsSummary()
	fmt.Println()

	for m.running {
		select {
		case <-ticker.C:
			m.printMonitor(fmt.Sprintf("🔍 Checking for new data... (%s)", time.Now().Format("15:04:05")))
			
			if err := m.checkForNewData(); err != nil {
				m.printError(fmt.Sprintf("Check failed: %v", err))
			}
			
			// Show alert summary every 10th check (every 5 minutes if checking every 30 seconds)
			if time.Now().Unix()%(int64(MonitorInterval.Seconds())*10) < int64(MonitorInterval.Seconds()) {
				m.getAlertsSummary()
			}
			
			fmt.Println()

		case sig := <-sigChan:
			m.printMonitor(fmt.Sprintf("Received signal: %v. Shutting down...", sig))
			m.running = false
		}
	}

	m.printMonitor("Monitor stopped")
}

func main() {
	monitor.Println("🏦 AML Real-Time Data Monitor")
	monitor.Println("Monitor BigQuery table for changes and trigger immediate AML processing")
	fmt.Println()

	// Initialize monitor
	amlMonitor, err := NewAMLMonitor()
	if err != nil {
		log.Fatalf("Failed to initialize AML monitor: %v", err)
	}
	defer amlMonitor.Close()

	// Start monitoring
	amlMonitor.start()
}