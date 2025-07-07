# AML Monitoring System

This is a professional Anti-Money Laundering dashboard built with R Shiny. The system processes transaction data and flags suspicious activities for investigation.

## What it does

The dashboard analyzes banking transactions and identifies potential money laundering patterns. It uses various detection rules to catch things like:

- Large cash deposits or withdrawals
- Unusual transaction patterns
- High-risk customer behavior
- Cross-border money movements

When something looks suspicious, it creates an alert that compliance teams can investigate.

## Running the dashboard

1. Make sure you have R installed with these packages:
   - shiny
   - shinydashboard
   - DT
   - htmltools

2. Run the system in levels:
   - First: `Rscript level1_basic_aml.R` (processes transactions and creates basic alerts)
   - Second: `Rscript level2_advanced_aml.R` (adds customer risk scoring)
   - Third: `Rscript run_professional_dashboard.R` (starts the web dashboard)

3. Open your browser to http://localhost:8080

## Dashboard features

**Executive Dashboard** - High-level metrics and charts showing alert volumes, risk distribution, and key performance indicators.

**Alert Center** - Detailed view of all suspicious activity alerts. You can filter by priority level and see transaction details.

**Customer Intelligence** - Risk profiles for customers, showing who's been flagged and why.

**Advanced Analytics** - Financial impact analysis and detection performance metrics.

**System Monitor** - Technical status showing if everything is running properly.

## File structure

- `level1_basic_aml.R` - Core transaction processing and alert generation
- `level2_advanced_aml.R` - Customer risk scoring and advanced analytics  
- `app_professional.R` - Main dashboard application
- `run_professional_dashboard.R` - Launcher script
- `data/` - Sample transaction files
- `outputs/` - Generated alerts and reports

## How alerts work

The system looks at each transaction and applies detection rules. If a transaction triggers multiple rules or exceeds certain thresholds, it gets flagged as suspicious. Alerts are ranked as HIGH, MEDIUM, or LOW priority based on risk factors.

Common triggers include:
- Transactions over $10,000
- Multiple transactions just under reporting limits
- Transactions to/from high-risk countries
- Customers with unusual activity patterns

## Data requirements

The system expects CSV files with transaction data including customer IDs, amounts, dates, and transaction types. Sample data is provided to test the system.

## Notes

This is a demonstration system for educational purposes. Real AML systems require integration with core banking systems, regulatory reporting capabilities, and proper security controls.

The dashboard uses a dark theme optimized for monitoring environments. All charts and tables are styled consistently with the professional color scheme.