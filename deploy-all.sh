#!/bin/bash

echo "🚀 Deploying Complete AML System to Google Cloud"
echo "=================================================="

PROJECT_ID="anlaytics-465216"
REGION="us-central1"

# Set project
gcloud config set project $PROJECT_ID

echo ""
echo "📊 Step 1: Deploying Cloud Function for automatic AML processing..."
echo "-------------------------------------------------------------------"

# Deploy Cloud Function
gcloud functions deploy aml-processor \
    --gen2 \
    --runtime=go121 \
    --region=$REGION \
    --source=functions/aml-processor \
    --entry-point=ProcessAMLAlerts \
    --trigger-topic=aml-bigquery-events \
    --memory=512Mi \
    --timeout=540s \
    --service-account=aml-service-account@$PROJECT_ID.iam.gserviceaccount.com

echo ""
echo "🔔 Step 2: Setting up BigQuery notifications..."
echo "-----------------------------------------------"

# Create Pub/Sub topic if it doesn't exist
gcloud pubsub topics create aml-bigquery-events || echo "Topic already exists"

# Create BigQuery notification (this requires additional setup in BigQuery console)
echo "⚠️  Note: You need to set up BigQuery table notifications manually:"
echo "   1. Go to BigQuery Console"
echo "   2. Select your credit_card_transactions table"
echo "   3. Set up notifications to publish to: projects/$PROJECT_ID/topics/aml-bigquery-events"

echo ""
echo "🎨 Step 3: Deploying R Shiny Dashboard to Cloud Run..."
echo "------------------------------------------------------"

# Deploy Dashboard using Cloud Build
gcloud builds submit --config cloudbuild.yaml

echo ""
echo "✅ Deployment Complete!"
echo "======================"
echo ""
echo "🏗️  Architecture Deployed:"
echo "   • Cloud Function: aml-processor (automatic AML processing)"
echo "   • Cloud Run: AML Dashboard (web interface)"
echo "   • BigQuery: Data storage and processing"
echo "   • Pub/Sub: Event-driven triggers"
echo ""
echo "🔄 Workflow:"
echo "   1. Upload CSV → BigQuery"
echo "   2. BigQuery triggers Pub/Sub event"
echo "   3. Cloud Function runs AML processing"
echo "   4. Dashboard shows updated alerts"
echo ""
echo "🌐 Access your dashboard at the Cloud Run URL provided above!"