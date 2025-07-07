# AML System Cloud Deployment Commands

This file contains all the commands needed to deploy the AML system from scratch to Google Cloud.

## Prerequisites

```bash
# Install Google Cloud SDK (macOS)
brew install google-cloud-sdk

# Verify installation
gcloud --version
```

## 1. Authentication & Project Setup

```bash
# Login to Google Cloud
gcloud auth login

# Set your project ID (replace with your actual project ID)
export PROJECT_ID="anlaytics-465216"
gcloud config set project $PROJECT_ID

# Set default account
gcloud config set account basalelr@gmail.com

# Verify current configuration
gcloud config list
```

## 2. Enable Required Google Cloud APIs

```bash
# Enable all required APIs in one command
gcloud services enable \
    bigquery.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    secretmanager.googleapis.com
```

## 3. BigQuery Setup

### Create Dataset
```bash
# Create BigQuery dataset for AML data
bq mk --dataset $PROJECT_ID:aml_data
```

### Upload Transaction Data
```bash
# Upload CSV file to BigQuery (adjust path if needed)
bq load \
    --source_format=CSV \
    --skip_leading_rows=1 \
    --autodetect \
    aml_data.credit_card_transactions \
    credit_card_transactions.csv
```

### Verify Data Upload
```bash
# Check tables in dataset
bq ls aml_data

# Check row count
bq query --use_legacy_sql=false \
'SELECT COUNT(*) as total_rows FROM `'$PROJECT_ID'.aml_data.credit_card_transactions`'

# Preview data
bq query --use_legacy_sql=false \
'SELECT * FROM `'$PROJECT_ID'.aml_data.credit_card_transactions` LIMIT 5'
```

## 4. Service Account Setup

```bash
# Create service account for AML system
gcloud iam service-accounts create aml-service-account \
    --display-name="AML System Service Account"

# Grant BigQuery permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:aml-service-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:aml-service-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.jobUser"
```

## 5. Secret Manager (Optional - for AI features)

```bash
# Create secret for OpenAI API key (if using Level 2 AI processing)
echo "your-openai-api-key-here" | gcloud secrets create openai-api-key --data-file=-

# Grant access to service account
gcloud secrets add-iam-policy-binding openai-api-key \
    --member="serviceAccount:aml-service-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
```

## 6. Docker Build & Deploy

### Build Container Image
```bash
# Navigate to project directory
cd "/path/to/AML-System"

# Build and push to Google Container Registry
gcloud builds submit --tag gcr.io/$PROJECT_ID/aml-system
```

### Deploy to Cloud Run
```bash
# Deploy with full configuration
gcloud run deploy aml-system \
    --image gcr.io/$PROJECT_ID/aml-system \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --service-account aml-service-account@$PROJECT_ID.iam.gserviceaccount.com \
    --set-env-vars GOOGLE_CLOUD_PROJECT=$PROJECT_ID \
    --memory 4Gi \
    --cpu 2 \
    --timeout 3600 \
    --port 8080
```

## 7. Monitoring & Management Commands

### Check Service Status
```bash
# List Cloud Run services
gcloud run services list --region us-central1

# Get service URL
gcloud run services describe aml-system \
    --region us-central1 \
    --format="value(status.url)"

# Check service details
gcloud run services describe aml-system --region us-central1
```

### View Logs
```bash
# View recent logs
gcloud run services logs read aml-system \
    --region us-central1 \
    --limit 50

# Tail logs in real-time
gcloud run services logs tail aml-system --region us-central1
```

### Check Build Status
```bash
# List recent builds
gcloud builds list --limit=5

# Get specific build details
gcloud builds describe BUILD_ID
```

## 8. BigQuery Data Verification

```bash
# Check all tables after processing
bq ls aml_data

# Count alerts generated
bq query --use_legacy_sql=false \
'SELECT COUNT(*) as alert_count FROM `'$PROJECT_ID'.aml_data.aml_alerts_level1`'

# View alert breakdown
bq query --use_legacy_sql=false \
'SELECT alert_type, priority, COUNT(*) as count 
 FROM `'$PROJECT_ID'.aml_data.aml_alerts_level1` 
 GROUP BY alert_type, priority'

# View recent alerts
bq query --use_legacy_sql=false \
'SELECT * FROM `'$PROJECT_ID'.aml_data.aml_alerts_level1` 
 ORDER BY alert_date DESC 
 LIMIT 10'
```

## 9. Update Deployment

### Rebuild and Redeploy
```bash
# Build new image
gcloud builds submit --tag gcr.io/$PROJECT_ID/aml-system

# Update service with new image
gcloud run services update aml-system \
    --image gcr.io/$PROJECT_ID/aml-system \
    --region us-central1
```

### Update Configuration Only
```bash
# Update environment variables
gcloud run services update aml-system \
    --set-env-vars GOOGLE_CLOUD_PROJECT=$PROJECT_ID,NEW_VAR=value \
    --region us-central1

# Update resource limits
gcloud run services update aml-system \
    --memory 8Gi \
    --cpu 4 \
    --region us-central1
```

## 10. Cleanup Commands

### Delete Service
```bash
# Delete Cloud Run service
gcloud run services delete aml-system --region us-central1
```

### Delete BigQuery Data
```bash
# Delete specific table
bq rm -t aml_data.aml_alerts_level1

# Delete entire dataset
bq rm -r aml_data
```

### Delete Container Images
```bash
# List images
gcloud container images list --repository gcr.io/$PROJECT_ID

# Delete specific image
gcloud container images delete gcr.io/$PROJECT_ID/aml-system:latest
```

## 11. Troubleshooting Commands

### Debug Container Startup
```bash
# Check service revisions
gcloud run revisions list --service aml-system --region us-central1

# Describe specific revision
gcloud run revisions describe REVISION_NAME --region us-central1
```

### Test Service Connectivity
```bash
# Get service URL
SERVICE_URL=$(gcloud run services describe aml-system \
    --region us-central1 \
    --format='value(status.url)')

# Test if service responds
curl -I $SERVICE_URL

# Test specific endpoint
curl $SERVICE_URL/health
```

### Check Resource Usage
```bash
# View metrics
gcloud run metrics list --service aml-system --region us-central1
```

## 12. Scheduled Processing (Optional)

### Create Cloud Scheduler Job
```bash
# Schedule daily processing at 2 AM
gcloud scheduler jobs create http aml-daily-processing \
    --schedule="0 2 * * *" \
    --uri="$SERVICE_URL/process" \
    --http-method=GET \
    --time-zone="America/New_York"

# List scheduled jobs
gcloud scheduler jobs list
```

## Complete Deployment Script

Save this as `deploy.sh`:

```bash
#!/bin/bash

# Set variables
export PROJECT_ID="anlaytics-465216"
export REGION="us-central1"
export SERVICE_NAME="aml-system"

# Setup
gcloud config set project $PROJECT_ID
gcloud services enable bigquery.googleapis.com run.googleapis.com cloudbuild.googleapis.com

# Create BigQuery dataset
bq mk --dataset $PROJECT_ID:aml_data

# Upload data
bq load --source_format=CSV --skip_leading_rows=1 --autodetect \
    aml_data.credit_card_transactions credit_card_transactions.csv

# Create service account
gcloud iam service-accounts create aml-service-account \
    --display-name="AML System Service Account"

# Grant permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:aml-service-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:aml-service-account@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/bigquery.jobUser"

# Build and deploy
gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME

gcloud run deploy $SERVICE_NAME \
    --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --service-account aml-service-account@$PROJECT_ID.iam.gserviceaccount.com \
    --set-env-vars GOOGLE_CLOUD_PROJECT=$PROJECT_ID \
    --memory 4Gi \
    --cpu 2 \
    --timeout 3600 \
    --port 8080

echo "Deployment complete!"
echo "Service URL: $(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.url)')"
```

Make executable and run:
```bash
chmod +x deploy.sh
./deploy.sh
```

## Environment Variables Reference

```bash
# Core settings
GOOGLE_CLOUD_PROJECT=anlaytics-465216
PORT=8080

# Optional AI settings
OPENAI_API_KEY=your-key-here  # From Secret Manager

# BigQuery settings
BQ_DATASET=aml_data
BQ_LOCATION=US
```

## Useful Aliases

Add to your `.bashrc` or `.zshrc`:

```bash
# AML project shortcuts
alias aml-logs='gcloud run services logs read aml-system --region us-central1 --limit 50'
alias aml-deploy='gcloud builds submit --tag gcr.io/anlaytics-465216/aml-system && gcloud run services update aml-system --image gcr.io/anlaytics-465216/aml-system --region us-central1'
alias aml-url='gcloud run services describe aml-system --region us-central1 --format="value(status.url)"'
alias aml-status='gcloud run services describe aml-system --region us-central1'
```