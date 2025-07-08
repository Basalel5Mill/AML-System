# AML Monitoring System

A complete anti-money laundering detection system that monitors banking transactions for suspicious activity. Built for financial institutions to comply with regulatory requirements and catch money laundering before it happens.


<p align="center">
  <img src="https://primary-production-2548.up.railway.app/wp-content/uploads/2025/07/aml-system.gif" alt="aml system" />
</p>

[Watch the demo video on YouTube](https://youtu.be/zBu0x9FD_d8)

## What this system does

This platform analyzes banking transactions in real-time and automatically flags suspicious patterns. It's designed to help compliance teams identify potential money laundering activities like:

- Structuring (breaking large amounts into smaller transactions to avoid reporting)
- Velocity anomalies (unusually rapid transaction patterns)
- Geographic inconsistencies (transactions across multiple states/countries in short timeframes)
- Round amount patterns (testing behavior with exact dollar amounts)

When suspicious activity is detected, the system generates prioritized alerts that compliance officers can investigate and potentially file Suspicious Activity Reports (SARs) with regulators.

## Architecture

The system uses a modern cloud-native architecture that separates heavy data processing from the user interface:

**BigQuery** handles all transaction processing and alert generation. Raw transaction data gets uploaded here, and SQL scripts automatically detect suspicious patterns. This approach can process millions of transactions in seconds and costs almost nothing for typical volumes.

**Go tools** provide fast data upload and real-time monitoring capabilities. These lightweight programs can upload new transaction data and immediately trigger processing, or continuously monitor for changes and respond instantly.

**R Shiny dashboard** serves as the web interface where analysts view alerts, generate reports, and monitor system performance. Since BigQuery does the heavy lifting, this can run on minimal resources.

**Google Cloud Run** hosts the dashboard with automatic scaling - it only runs (and costs money) when someone is actually using it.

## Getting started

### Prerequisites
- Google Cloud account with BigQuery enabled
- Go 1.21+ for the upload/monitoring tools
- R with required packages for the dashboard

### Quick setup

1. **Set up BigQuery tables**
   ```bash
   bq query --use_legacy_sql=false < sql/setup_metadata_table.sql
   ```

2. **Build the Go tools**
   ```bash
   make build
   ```

3. **Upload your transaction data**
   ```bash
   make upload CSV=your_transactions.csv
   ```

4. **Start the professional dashboard**
   ```bash
   Rscript run_professional_dashboard.R
   ```

The dashboard will be available at http://localhost:8080

## Cloud Deployment

### Deploy to Google Cloud Run

1. **Prerequisites**
   ```bash
   # Install and authenticate with Google Cloud SDK
   gcloud auth login
   gcloud config set project anlaytics-465216
   
   # Enable required services
   gcloud services enable bigquery.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   gcloud services enable run.googleapis.com
   gcloud services enable secretmanager.googleapis.com
   ```

2. **Set up authentication**
   ```bash
   # Create service account
   gcloud iam service-accounts create aml-service-account --display-name="AML Service Account"
   
   # Grant BigQuery permissions
   gcloud projects add-iam-policy-binding anlaytics-465216 \
       --member="serviceAccount:aml-service-account@anlaytics-465216.iam.gserviceaccount.com" \
       --role="roles/bigquery.jobUser"
   
   gcloud projects add-iam-policy-binding anlaytics-465216 \
       --member="serviceAccount:aml-service-account@anlaytics-465216.iam.gserviceaccount.com" \
       --role="roles/bigquery.dataEditor"
   
   # Create and download service account key
   gcloud iam service-accounts keys create ~/aml-key.json \
       --iam-account=aml-service-account@anlaytics-465216.iam.gserviceaccount.com
   
   export GOOGLE_APPLICATION_CREDENTIALS=~/aml-key.json
   ```

3. **Deploy complete system**
   ```bash
   chmod +x deploy-all.sh
   ./deploy-all.sh
   ```

4. **Set up secure API key storage**
   ```bash
   # Store OpenAI API key in Secret Manager
   echo "your-openai-api-key" | gcloud secrets create openai-api-key --data-file=-
   
   # Grant Cloud Run access to secret
   gcloud secrets add-iam-policy-binding openai-api-key \
       --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
       --role="roles/secretmanager.secretAccessor"
   
   # Update Cloud Run service
   gcloud run services update aml-dashboard \
       --update-secrets=OPENAI_API_KEY=openai-api-key:latest \
       --region=us-central1
   ```

5. **Enable public access**
   ```bash
   gcloud run services update aml-dashboard \
       --allow-unauthenticated \
       --region=us-central1
   ```

### Deployment URLs
- **Dashboard:** `https://aml-dashboard-PROJECT_NUMBER.us-central1.run.app`
- **Cloud Function:** `aml-processor` (triggers automatically)

## Troubleshooting

### Common Issues

**1. Docker build fails with "pandoc-citeproc" error**
- This package is obsolete in newer Debian versions
- The Dockerfile has been updated to exclude it

**2. Go build fails with BigQuery API errors**
- Ensure you're using the correct BigQuery Go client API
- The source configuration should be on `bigquery.NewReaderSource()`, not the loader

**3. Cloud Run "403 Forbidden" error**
- Set authentication to "Allow unauthenticated invocations" in Security tab
- Or run: `gcloud run services update aml-dashboard --allow-unauthenticated --region=us-central1`

**4. Secret Manager permission denied**
- Grant the Cloud Run service account access to secrets:
  ```bash
  gcloud secrets add-iam-policy-binding openai-api-key \
      --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
      --role="roles/secretmanager.secretAccessor"
  ```

**5. BigQuery table not found**
- Ensure dataset exists: `bq mk --dataset --location=US anlaytics-465216:aml_data`
- Run setup script: `bq query --use_legacy_sql=false < sql/setup_metadata_table.sql`

**6. R package compilation takes too long**
- The Dockerfile installs many packages; first build takes 15-20 minutes
- Subsequent builds use cached layers and are much faster
- Consider using binary packages for faster builds

### Performance Optimization

**Cost-Efficient Settings:**
- Cloud Run: 1GB RAM, 1 CPU, scale to zero
- Cloud Function: 512MB RAM, auto-scaling
- BigQuery: Pay per query, no always-on costs

**Build Optimization:**
- Use `.gcloudignore` to exclude unnecessary files
- Docker layer caching reduces rebuild times
- Binary R packages install faster than source compilation

## Data processing workflow

The system processes data in stages:

1. **Raw data upload** - Transaction CSV files get loaded into BigQuery
2. **Alert generation** - SQL scripts analyze transactions and create alerts for suspicious patterns
3. **Risk scoring** - Customer profiles are updated based on their transaction history and alert patterns
4. **Dashboard display** - Analysts view prioritized alerts and investigation details

Processing happens automatically whenever new data is uploaded. The system only analyzes new transactions since the last run, making it efficient for daily updates.

## Tools and commands

### Upload tool
Uploads transaction data and immediately processes it for alerts:
```bash
make upload CSV=transactions.csv
```

### Real-time monitor
Continuously watches for new data and processes it automatically:
```bash
make monitor
```

### Manual processing
If you need to reprocess all data:
```bash
bq query --use_legacy_sql=false < sql/run_all_aml_processing.sql
```

## Dashboard options

**Professional Dashboard** (Recommended):
```bash
Rscript run_professional_dashboard.R
```
- Dark theme with off-white accents
- Advanced analytics and AI insights
- Executive-level reporting

**Basic Dashboard**:
```bash
Rscript app.R
```
- Simple interface for basic monitoring

## Dashboard features

**Executive Dashboard** - Overview metrics showing total alerts, high-priority cases, and customers under investigation. Includes charts showing alert distribution by type and priority.

**Alert Center** - Detailed view of all suspicious activity alerts with filtering and search capabilities. Each alert shows the customer, transaction details, risk score, and recommended actions.

**Customer Intelligence** - Risk profiles showing which customers have been flagged and why. Includes transaction history, risk category, and alert patterns.

**Advanced Analytics** - Financial impact analysis, detection performance metrics, and trend analysis over time.

**AI Insights** - Automated reports and summaries generated using OpenAI integration for executive briefings and regulatory documentation.

**System Monitor** - Real-time status showing processing performance, system health, and compliance metrics.

## File organization

```
sql/                    # BigQuery processing scripts
├── setup_metadata_table.sql           # Initial table setup
├── incremental_aml_processing.sql      # Main processing logic
├── velocity_detection.sql             # Speed-based alerts
├── structuring_detection.sql          # Threshold avoidance detection
└── geographic_detection.sql           # Location-based alerts

cmd/                    # Go command-line tools
├── upload/main.go      # Data upload with immediate processing
└── monitor/main.go     # Real-time monitoring service

scripts/                # R processing scripts (legacy)
├── level1_data_loading.R               # Data preprocessing
├── level1_aml_detection.R              # Alert generation
└── level2_ai_integration.R             # AI-powered reporting

app.R                   # Main dashboard application
Makefile               # Build and deployment commands
```

## Alert types and detection logic

**Velocity Alerts** - Triggered when a customer makes 5+ transactions within 5 minutes. This often indicates automated testing or rapid movement of funds to avoid detection.

**Structuring Alerts** - Flagged when customers make multiple transactions between $9,000-$9,999 on the same day. This is a common technique to stay under the $10,000 reporting threshold.

**Geographic Alerts** - Generated when customers transact in multiple states or too many cities in a single day, which may indicate account compromise or coordinated money movement.

**Pattern Recognition** - The system learns normal transaction patterns for each customer and flags significant deviations in amounts, timing, or merchant types.

Each alert gets a risk score from 1-100 and priority classification (HIGH/MEDIUM/LOW) based on the severity and number of triggered rules.

## Regulatory compliance

The system is designed to help meet Bank Secrecy Act (BSA) and FinCEN requirements for suspicious activity monitoring. It maintains audit trails of all alerts, provides risk-based customer classification, and generates reports suitable for regulatory review.

All processing is logged with timestamps, and the system tracks which transactions have been analyzed to ensure complete coverage without gaps.

## How it works and what it does

This system monitors banking transactions to catch money laundering patterns. Here's what happens:

**Data Upload** - You upload transaction CSV files using the Go upload tool. This puts your data into BigQuery where it can be processed quickly.

**Alert Detection** - SQL scripts automatically run to find suspicious patterns like customers making many small transactions to avoid reporting thresholds, or rapid-fire transactions that look like testing behavior.

**Risk Scoring** - Each customer gets a risk score based on their transaction history and any alerts they've triggered. High-risk customers get flagged for investigation.

**Dashboard Monitoring** - Compliance analysts use the web dashboard to review alerts, see customer risk profiles, and generate reports for regulators.

**Real-time Processing** - The system can either process data on a schedule or immediately when new transactions are uploaded. It only looks at new data since the last run, so it stays fast even with large datasets.

The whole thing runs on Google Cloud and scales automatically. You don't need to manage servers or worry about infrastructure - just upload data and monitor the results.

## Development and customization

The detection rules are implemented in SQL and can be modified in the `sql/` directory. Risk scoring weights and thresholds are configurable in the processing scripts.

The dashboard is built with R Shiny and supports custom themes, additional charts, and integration with external data sources.

The Go tools can be extended for additional data sources, different file formats, or integration with other monitoring systems.

## Security considerations

This is a demonstration system showing AML detection concepts. Production deployments should include:

- Encryption at rest and in transit
- Access controls and audit logging  
- Network security and VPC isolation
- Regular security assessments
- Proper key management
- Data retention and privacy controls

The system does not store or transmit actual customer data - all examples use synthetic transaction records for testing purposes.

# Automatic AML Processing System

This system automatically processes new transaction data and generates alerts using BigQuery scheduled queries.

## Quick Start

### 1. Initial Setup
```bash
# Run once to set up metadata tables
bq query --use_legacy_sql=false < sql/setup_metadata_table.sql
```

### 2. Update Data
```bash
# Upload new transaction data
./scripts/upload_new_data.sh your_new_transactions.csv
```

### 3. Set Up Automation
```bash
# Create scheduled query (runs every 30 minutes)
gcloud scheduler jobs create bigquery aml-processing-scheduler \
    --schedule="*/30 * * * *" \
    --location=us-central1 \
    --max-retry-attempts=3 \
    --query-file=sql/incremental_aml_processing.sql \
    --use-legacy-sql=false \
    --project=anlaytics-465216
```

##  How It Works

1. **Upload CSV** → Replaces BigQuery raw data table
2. **Scheduled Query** → Runs every 30 minutes automatically  
3. **Incremental Processing** → Only processes new records since last run
4. **Smart Detection** → Skips processing if no new data found
5. **Dashboard Updates** → Shows new alerts automatically

## 💰 Cost Efficiency

- **Processing**: Only runs when new data exists
- **Incremental**: Processes only new records, not entire dataset
- **No Cloud Functions**: Uses native BigQuery scheduling
- **Estimated Cost**: $5-15/month for 1.3M daily records

## Workflow

```
CSV Update → BigQuery Table → Scheduled Query → New Alerts → Dashboard
```

## 📁 Files Created

- `sql/setup_metadata_table.sql` - Initial table setup
- `sql/incremental_aml_processing.sql` - Main processing logic  
- `sql/setup_scheduled_query.sql` - Scheduling instructions
- `scripts/upload_new_data.sh` - Data upload script
- `README_AUTO_PROCESSING.md` - This documentation

## 🛠️ Manual Processing

If you need to process data immediately:
```bash
bq query --use_legacy_sql=false < sql/incremental_aml_processing.sql
```

## 📈 Monitoring

Check processing status:
```sql
SELECT * FROM `anlaytics-465216.aml_data.processing_metadata`;
```

View recent alerts:
```sql
SELECT * FROM `anlaytics-465216.aml_data.aml_alerts_level1` 
ORDER BY created_at DESC LIMIT 10;
```

## 🎯 Benefits

- ✅ **Automatic** - No manual intervention needed
- ✅ **Efficient** - Only processes new data
- ✅ **Cheap** - Native BigQuery solution
- ✅ **Scalable** - Handles millions of records
- ✅ **Reliable** - Built-in retry and error handling

# AML System - Go Implementation

High-performance, real-time AML monitoring system built with Go for optimal speed and resource efficiency.

## 🚀 Quick Start

### Prerequisites
- Go 1.21+
- Google Cloud SDK configured
- BigQuery access

### Setup
```bash
# Download dependencies
make deps

# Build all tools
make build

# Or use the quick setup
make setup
```

## 📁 Project Structure

```
cmd/
├── upload/     # CSV upload and immediate processing
└── monitor/    # Real-time data monitoring

sql/            # BigQuery SQL scripts
Makefile        # Build and run commands
go.mod          # Go module dependencies
```

## 🛠️ Tools

### 1. Upload Tool
Uploads CSV to BigQuery and triggers immediate AML processing.

```bash
# Upload specific file
make upload CSV=new_transactions.csv

# Upload default file (credit_card_transactions.csv)
make upload

# Development mode
make run-upload CSV=your_file.csv
```

**Features:**
- ✅ Real-time progress tracking
- ✅ Colored terminal output
- ✅ File validation and verification
- ✅ Immediate AML processing trigger
- ✅ Error handling and retry logic

### 2. Real-Time Monitor
Continuously monitors BigQuery table for changes and triggers processing automatically.

```bash
# Start real-time monitoring
make monitor

# Development mode
make run-monitor
```

**Features:**
- ✅ Real-time row count monitoring (every 30 seconds)
- ✅ Automatic processing trigger on new data
- ✅ Alert summary reporting
- ✅ Graceful shutdown (Ctrl+C)
- ✅ Memory efficient (< 50MB RAM)

## 💰 Performance & Cost

### Resource Usage
- **Upload Tool**: ~30MB RAM, runs for seconds
- **Monitor**: ~20-50MB RAM, runs continuously
- **CPU**: Minimal usage (< 5%)

### Cost Efficiency
- **BigQuery**: Free tier (< 1TB processing/month)
- **Cloud Run**: $3-8/month (only when dashboard accessed)
- **Total**: ~$3-8/month for complete AML system

## 🔄 Workflows

### Batch Processing
```bash
# 1. Upload new data
make upload CSV=today_transactions.csv

# 2. Processing happens immediately
# 3. Dashboard shows fresh alerts
```

### Real-Time Monitoring
```bash
# 1. Start monitor
make monitor

# 2. Upload data from another terminal
make upload CSV=new_data.csv

# 3. Monitor detects changes and processes automatically
```

## 📊 Output Examples

### Upload Tool Output
```
[INFO] File: transactions.csv (45.2 MB, ~1,234,567 records)
[INFO] Current table has 0 rows
[PROCESSING] Uploading CSV to BigQuery...
[SUCCESS] CSV uploaded successfully!
[SUCCESS] Table now has 1,234,567 rows
[PROCESSING] 🚀 Triggering AML processing...
[SUCCESS] AML processing completed successfully!
[SUCCESS] 🎉 Complete pipeline finished in 89.3 seconds!
```

### Monitor Output
```
[MONITOR] 🔍 Starting AML Real-Time Monitor
[INFO] Monitoring table: anlaytics-465216.aml_data.credit_card_transactions
[MONITOR] 🔔 New data detected! 5,432 new rows (total: 1,240,000)
[MONITOR] 🚀 Triggering AML processing due to new data...
[SUCCESS] AML processing completed successfully!
[INFO] 📊 Today's Alert Summary:
   • VELOCITY (HIGH): 12 alerts
   • STRUCTURING (MEDIUM): 8 alerts
```

## 🏗️ Building for Production

### Single Platform
```bash
make build
```

### Multi-Platform
```bash
make build-all
# Creates binaries for Linux, macOS, and Windows
```

### Global Installation
```bash
make install
# Installs to /usr/local/bin/
# Use: aml-upload or aml-monitor from anywhere
```

## 🐳 Docker Deployment

```dockerfile
# Add to existing Dockerfile for Cloud Run
COPY bin/upload /usr/local/bin/aml-upload
COPY bin/monitor /usr/local/bin/aml-monitor
```

## 🔧 Configuration

### Environment Variables
```bash
export GOOGLE_CLOUD_PROJECT=anlaytics-465216
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

### Monitoring Interval
Edit `cmd/monitor/main.go`:
```go
const MonitorInterval = 10 * time.Second // Check every 10 seconds
```

## 🧪 Testing

```bash
# Run all tests
make test

# Clean build artifacts
make clean
```

## 🔍 Troubleshooting

### Authentication Issues
```bash
# Login with gcloud
gcloud auth application-default login

# Set project
gcloud config set project anlaytics-465216
```

### BigQuery Permissions
```bash
# Grant BigQuery access to service account
gcloud projects add-iam-policy-binding anlaytics-465216 \
    --member="serviceAccount:aml-service-account@anlaytics-465216.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor"
```

## 🎯 Why Go?

- **🚀 Performance**: 10-100x faster than Python for I/O operations
- **💾 Memory Efficient**: Uses 50-90% less RAM than equivalent Python
- **⚡ Real-Time**: Perfect for continuous monitoring
- **📦 Single Binary**: No dependency management in production
- **🔄 Concurrency**: Built-in goroutines for monitoring multiple sources
- **🛡️ Reliability**: Strong typing and error handling

## 📈 Monitoring Integration

The Go tools integrate seamlessly with:
- BigQuery scheduled queries
- R Shiny dashboard
- Cloud Run deployment
- Alert generation pipeline

## 🎉 Benefits

- ✅ **Immediate Processing**: No 30-minute wait times
- ✅ **Real-Time Monitoring**: Detect changes instantly  
- ✅ **Resource Efficient**: Minimal memory and CPU usage
- ✅ **Cost Effective**: Runs on smallest Cloud Run instances
- ✅ **Production Ready**: Error handling, logging, graceful shutdown
- ✅ **Cross Platform**: Works on Linux, macOS, Windows