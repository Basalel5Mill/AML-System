# ============================================================================
# LEVEL 1: DATA LOADING AND PREPROCESSING
# ============================================================================

library(dplyr)
library(readr)
library(lubridate)
library(stringr)
library(bigrquery)
library(DBI)

# Configuration
PROJECT_ID <- Sys.getenv("GOOGLE_CLOUD_PROJECT", "anlaytics-465216")
DATASET_ID <- "aml_data"
TABLE_NAME <- "credit_card_transactions"
DATA_PROCESSED_PATH <- "data/processed/transactions_clean.csv"

# Create output directories
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/reports", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/alerts", recursive = TRUE, showWarnings = FALSE)

# Load transaction data from BigQuery
load_transaction_data <- function() {
  cat("🔄 Loading transaction data from BigQuery...\n")
  cat("📡 Project:", PROJECT_ID, "\n")
  cat("📊 Dataset:", DATASET_ID, "\n")
  cat("📋 Table:", TABLE_NAME, "\n")
  
  tryCatch({
    # Connect to BigQuery
    con <- dbConnect(
      bigrquery::bigquery(),
      project = PROJECT_ID,
      dataset = DATASET_ID
    )
    
    # Query all data
    sql <- paste0("SELECT * FROM `", PROJECT_ID, ".", DATASET_ID, ".", TABLE_NAME, "`")
    cat("🔍 SQL Query:", sql, "\n")
    
    transactions <- dbGetQuery(con, sql)
    dbDisconnect(con)
    
    # Convert data types
    transactions <- transactions %>%
      mutate(
        trans_date_trans_time = as.POSIXct(trans_date_trans_time),
        dob = as.Date(dob),
        is_fraud = as.logical(is_fraud)
      )
    
    cat("✅ Successfully loaded", nrow(transactions), "transactions from BigQuery\n")
    return(transactions)
    
  }, error = function(e) {
    cat("❌ Error loading from BigQuery:", e$message, "\n")
    cat("🔄 Falling back to local CSV file...\n")
    
    # Fallback to CSV if BigQuery fails
    if (file.exists("credit_card_transactions.csv")) {
      transactions <- read_csv("credit_card_transactions.csv", 
                              col_types = cols(
                                trans_date_trans_time = col_datetime(),
                                cc_num = col_double(),
                                merchant = col_character(),
                                category = col_character(),
                                amt = col_double(),
                                first = col_character(),
                                last = col_character(),
                                gender = col_character(),
                                street = col_character(),
                                city = col_character(),
                                state = col_character(),
                                zip = col_character(),
                                lat = col_double(),
                                long = col_double(),
                                city_pop = col_double(),
                                job = col_character(),
                                dob = col_date(),
                                trans_num = col_character(),
                                unix_time = col_double(),
                                merch_lat = col_double(),
                                merch_long = col_double(),
                                is_fraud = col_logical()
                              ))
      cat("✅ Loaded", nrow(transactions), "transactions from CSV fallback\n")
      return(transactions)
    } else {
      stop("❌ No data source available. BigQuery failed and no local CSV found.")
    }
  })
}

# Preprocess transaction data
preprocess_transaction_data <- function(transactions) {
  cat("🔄 Preprocessing transaction data...\n")
  
  processed_transactions <- transactions %>%
    # Create derived columns
    mutate(
      # Customer identifier
      customer_id = paste(first, last, sep = "_"),
      
      # Date/time features
      transaction_date = as.Date(trans_date_trans_time),
      transaction_hour = hour(trans_date_trans_time),
      transaction_minute = minute(trans_date_trans_time),
      transaction_day_of_week = weekdays(transaction_date),
      transaction_month = month(transaction_date),
      transaction_year = year(transaction_date),
      
      # Amount features
      amount_rounded = round(amt, 2),
      is_round_amount = amt %in% c(100, 200, 500, 1000, 2000, 5000, 10000),
      amount_category = case_when(
        amt < 50 ~ "Small",
        amt < 200 ~ "Medium", 
        amt < 1000 ~ "Large",
        TRUE ~ "Very Large"
      ),
      
      # Time-based features
      is_weekend = transaction_day_of_week %in% c("Saturday", "Sunday"),
      is_night_transaction = transaction_hour >= 22 | transaction_hour <= 6,
      is_business_hours = transaction_hour >= 9 & transaction_hour <= 17,
      
      # Geographic features
      state_clean = str_to_upper(str_trim(state)),
      city_clean = str_to_title(str_trim(city)),
      
      # Merchant features
      merchant_clean = str_to_title(str_trim(merchant)),
      category_clean = str_to_lower(str_trim(category)),
      
      # Customer demographics
      age = as.numeric(difftime(transaction_date, dob, units = "days")) / 365.25,
      age_group = case_when(
        age < 25 ~ "Young",
        age < 40 ~ "Adult",
        age < 60 ~ "Middle-aged",
        TRUE ~ "Senior"
      ),
      
      # Distance calculation (approximate)
      distance_km = sqrt((lat - merch_lat)^2 + (long - merch_long)^2) * 111.32,
      is_distant_transaction = distance_km > 100,
      
      # AML risk indicators
      is_high_amount = amt > 5000,
      is_cash_equivalent = category_clean %in% c("gas_transport", "grocery_pos", "misc_pos"),
      is_high_risk_merchant = category_clean %in% c("gambling", "adult", "tobacco"),
      
      # Fraud flag (if available)
      fraud_flag = ifelse(is.na(is_fraud), FALSE, is_fraud)
    ) %>%
    
    # Remove rows with critical missing data
    filter(
      !is.na(customer_id),
      !is.na(amt),
      !is.na(transaction_date),
      !is.na(merchant),
      !is.na(category),
      amt > 0  # Remove negative or zero amounts
    ) %>%
    
    # Arrange by customer and date
    arrange(customer_id, trans_date_trans_time) %>%
    
    # Add transaction sequence number per customer
    group_by(customer_id) %>%
    mutate(
      transaction_sequence = row_number(),
      days_since_first_transaction = as.numeric(transaction_date - min(transaction_date))
    ) %>%
    ungroup()
  
  cat("✅ Preprocessing completed\n")
  cat("📊 Final dataset:", nrow(processed_transactions), "transactions\n")
  cat("📊 Unique customers:", n_distinct(processed_transactions$customer_id), "\n")
  cat("📊 Date range:", min(processed_transactions$transaction_date), 
      "to", max(processed_transactions$transaction_date), "\n")
  
  return(processed_transactions)
}

# Generate summary statistics
generate_summary_statistics <- function(transactions) {
  cat("📊 Generating summary statistics...\n")
  
  summary_stats <- list(
    total_transactions = nrow(transactions),
    unique_customers = n_distinct(transactions$customer_id),
    unique_merchants = n_distinct(transactions$merchant),
    total_amount = sum(transactions$amt, na.rm = TRUE),
    avg_amount = mean(transactions$amt, na.rm = TRUE),
    date_range = paste(min(transactions$transaction_date), "to", 
                       max(transactions$transaction_date)),
    fraud_rate = mean(transactions$fraud_flag, na.rm = TRUE) * 100
  )
  
  cat("📋 TRANSACTION SUMMARY\n")
  cat("Total Transactions:", format(summary_stats$total_transactions, big.mark = ","), "\n")
  cat("Unique Customers:", format(summary_stats$unique_customers, big.mark = ","), "\n")
  cat("Unique Merchants:", format(summary_stats$unique_merchants, big.mark = ","), "\n")
  cat("Total Amount: $", format(round(summary_stats$total_amount), big.mark = ","), "\n")
  cat("Average Amount: $", round(summary_stats$avg_amount, 2), "\n")
  cat("Date Range:", summary_stats$date_range, "\n")
  cat("Known Fraud Rate:", round(summary_stats$fraud_rate, 2), "%\n")
  
  return(summary_stats)
}

# Main execution function
main_data_loading <- function() {
  cat("🚀 Starting Level 1: Data Loading and Preprocessing\n")
  
  # Load raw data from BigQuery
  raw_transactions <- load_transaction_data()
  
  # Preprocess data
  clean_transactions <- preprocess_transaction_data(raw_transactions)
  
  # Generate summary statistics
  summary_stats <- generate_summary_statistics(clean_transactions)
  
  # Save processed data
  write_csv(clean_transactions, DATA_PROCESSED_PATH)
  cat("💾 Processed data saved to:", DATA_PROCESSED_PATH, "\n")
  
  # Save summary statistics
  saveRDS(summary_stats, "outputs/reports/summary_statistics.rds")
  
  cat("✅ Level 1 data loading completed successfully!\n")
  
  return(clean_transactions)
}

# Execute if running directly
if (!exists("transactions_clean")) {
  transactions_clean <- main_data_loading()
}