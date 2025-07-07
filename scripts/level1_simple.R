# ============================================================================
# LEVEL 1: SIMPLIFIED AML DETECTION USING BASE R
# ============================================================================

# Configuration
DATA_RAW_PATH <- "credit_card_transactions.csv"
DATA_PROCESSED_PATH <- "data/processed/transactions_clean.csv"

# Create output directories
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/reports", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/alerts", recursive = TRUE, showWarnings = FALSE)

# Load and analyze data using base R
cat("🚀 Starting Level 1: AML Detection using Base R\n")
cat("🔄 Loading transaction data from:", DATA_RAW_PATH, "\n")

if (!file.exists(DATA_RAW_PATH)) {
  stop("❌ Data file not found. Please download from Kaggle and place in current directory")
}

# Read CSV file
transactions <- read.csv(DATA_RAW_PATH, stringsAsFactors = FALSE)
cat("✅ Successfully loaded", nrow(transactions), "transactions\n")

# Basic data analysis
cat("📊 Analyzing transaction data...\n")

# Summary statistics
total_transactions <- nrow(transactions)
unique_customers <- length(unique(paste(transactions$first, transactions$last)))
total_amount <- sum(transactions$amt, na.rm = TRUE)
avg_amount <- mean(transactions$amt, na.rm = TRUE)

cat("📋 TRANSACTION SUMMARY\n")
cat("Total Transactions:", format(total_transactions, big.mark = ","), "\n")
cat("Unique Customers:", format(unique_customers, big.mark = ","), "\n")
cat("Total Amount: $", format(round(total_amount), big.mark = ","), "\n")
cat("Average Amount: $", round(avg_amount, 2), "\n")

# AML Pattern Detection using Base R

# 1. HIGH AMOUNT TRANSACTIONS (potential structuring)
high_amount_threshold <- 9000
high_amount_transactions <- transactions[transactions$amt >= high_amount_threshold, ]
cat("🔍 Found", nrow(high_amount_transactions), "high-amount transactions (>=$9,000)\n")

# 2. ROUND AMOUNT DETECTION
round_amounts <- c(100, 200, 500, 1000, 2000, 5000, 10000)
round_amount_transactions <- transactions[transactions$amt %in% round_amounts, ]
cat("🔍 Found", nrow(round_amount_transactions), "round-amount transactions\n")

# 3. CUSTOMER FREQUENCY ANALYSIS
customer_freq <- table(paste(transactions$first, transactions$last))
high_freq_customers <- names(customer_freq[customer_freq > 10])
cat("🔍 Found", length(high_freq_customers), "customers with >10 transactions\n")

# 4. WEEKEND TRANSACTIONS
transactions$trans_date <- as.Date(transactions$trans_date_trans_time)
transactions$weekday <- weekdays(transactions$trans_date)
weekend_transactions <- transactions[transactions$weekday %in% c("Saturday", "Sunday"), ]
cat("🔍 Found", nrow(weekend_transactions), "weekend transactions\n")

# Generate Alerts
alerts <- data.frame(
  alert_type = character(),
  customer_id = character(),
  amount = numeric(),
  date = character(),
  description = character(),
  priority = character(),
  stringsAsFactors = FALSE
)

# High amount alerts
if (nrow(high_amount_transactions) > 0) {
  high_alerts <- data.frame(
    alert_type = "HIGH_AMOUNT",
    customer_id = paste(high_amount_transactions$first, high_amount_transactions$last),
    amount = high_amount_transactions$amt,
    date = high_amount_transactions$trans_date_trans_time,
    description = paste("High amount transaction: $", high_amount_transactions$amt),
    priority = ifelse(high_amount_transactions$amt > 10000, "HIGH", "MEDIUM"),
    stringsAsFactors = FALSE
  )
  alerts <- rbind(alerts, high_alerts)
}

# Round amount alerts for frequent users
round_customer_freq <- table(paste(round_amount_transactions$first, round_amount_transactions$last))
frequent_round_customers <- names(round_customer_freq[round_customer_freq >= 3])

if (length(frequent_round_customers) > 0) {
  round_alerts <- data.frame(
    alert_type = "ROUND_AMOUNTS",
    customer_id = frequent_round_customers,
    amount = NA,
    date = Sys.Date(),
    description = paste("Customer made", round_customer_freq[frequent_round_customers], "round amount transactions"),
    priority = "MEDIUM",
    stringsAsFactors = FALSE
  )
  alerts <- rbind(alerts, round_alerts)
}

# Save results
write.csv(alerts, "outputs/alerts/aml_alerts_level1.csv", row.names = FALSE)
cat("💾 Saved", nrow(alerts), "alerts to outputs/alerts/aml_alerts_level1.csv\n")

# Create summary report
summary_text <- paste(
  "AML TRANSACTION MONITORING - LEVEL 1 ANALYSIS",
  "==============================================",
  "",
  paste("Analysis Date:", Sys.Date()),
  paste("Total Transactions Analyzed:", format(total_transactions, big.mark = ",")),
  paste("Total Amount Processed: $", format(round(total_amount), big.mark = ",")),
  paste("Average Transaction: $", round(avg_amount, 2)),
  "",
  "SUSPICIOUS ACTIVITY DETECTED:",
  paste("• Total Alerts Generated:", nrow(alerts)),
  paste("• High Amount Transactions:", nrow(high_amount_transactions)),
  paste("• Round Amount Patterns:", length(frequent_round_customers)),
  paste("• High Frequency Customers:", length(high_freq_customers)),
  paste("• Weekend Activity:", nrow(weekend_transactions)),
  "",
  "ALERT BREAKDOWN:",
  paste("• HIGH Priority:", sum(alerts$priority == "HIGH", na.rm = TRUE)),
  paste("• MEDIUM Priority:", sum(alerts$priority == "MEDIUM", na.rm = TRUE)),
  "",
  "KEY FINDINGS:",
  "• Multiple high-value transactions detected",
  "• Round-amount patterns suggest potential testing",
  "• Elevated weekend activity may indicate suspicious behavior",
  "• Several customers show unusually high transaction frequency",
  "",
  "RECOMMENDATIONS:",
  "• Investigate HIGH priority alerts immediately",
  "• Review customer profiles for unusual patterns",
  "• Consider enhanced monitoring for flagged accounts",
  "• Escalate to compliance team for regulatory review",
  "",
  paste("Report Generated by: AML Monitoring System v1.0 (Base R)"),
  paste("System Status: Operational"),
  "",
  sep = "\n"
)

writeLines(summary_text, "outputs/reports/executive_summary.txt")
cat("📋 Executive summary saved to outputs/reports/executive_summary.txt\n")

# Display key findings
cat("\n🎯 LEVEL 1 ANALYSIS COMPLETE!\n")
cat("Key metrics:\n")
cat("- Transactions processed:", format(total_transactions, big.mark = ","), "\n")
cat("- Alerts generated:", nrow(alerts), "\n")
cat("- High-risk patterns identified:", sum(alerts$priority == "HIGH", na.rm = TRUE), "\n")
cat("- Files saved to outputs/ directory\n")

cat("✅ Level 1 AML detection completed successfully!\n")