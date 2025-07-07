# AML Monitoring System

A complete anti-money laundering detection system that monitors banking transactions for suspicious activity. Built for financial institutions to comply with regulatory requirements and catch money laundering before it happens.

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

4. **Start the dashboard**
   ```bash
   Rscript app.R
   ```

The dashboard will be available at http://localhost:8080

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