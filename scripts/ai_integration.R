# ============================================================================
# LEVEL 2: AI INTEGRATION FOR AML REPORTING
# ============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(readr)
library(stringr)

# AI Configuration
AI_CONFIG <- list(
  openai_api_url = "https://api.openai.com/v1/chat/completions",
  model = "gpt-3.5-turbo",  # Use gpt-4 if you have access
  max_tokens = 1500,
  temperature = 0.3,
  timeout = 30,
  retry_attempts = 3,
  
  # Prompt templates
  prompts = list(
    executive_summary = "You are a senior financial crimes analyst at KPMG. Based on the AML analysis results provided, create a professional executive summary for bank leadership. Focus on key findings, regulatory implications, and recommended actions. Use a formal, consulting tone.",
    
    technical_analysis = "You are a technical AML specialist. Analyze the provided alert data and create a detailed technical report covering detection methodologies, pattern analysis, and investigation priorities.",
    
    compliance_report = "You are a compliance officer preparing a report for regulators. Based on the AML findings, create a comprehensive compliance report that addresses regulatory requirements and demonstrates due diligence.",
    
    risk_assessment = "You are a risk management consultant. Evaluate the AML findings and create a risk assessment report that quantifies potential financial impact and recommends mitigation strategies."
  )
)

# Setup OpenAI API
setup_openai_api <- function() {
  # Check for API key in environment
  api_key <- Sys.getenv("OPENAI_API_KEY")
  
  if (api_key == "") {
    # Try to load from .env file
    if (file.exists(".env")) {
      env_vars <- readLines(".env")
      api_key_line <- grep("OPENAI_API_KEY", env_vars, value = TRUE)
      if (length(api_key_line) > 0) {
        api_key <- gsub("OPENAI_API_KEY=", "", api_key_line)
        Sys.setenv(OPENAI_API_KEY = api_key)
      }
    }
  }
  
  if (api_key == "") {
    stop("❌ OpenAI API key not found. Please set OPENAI_API_KEY environment variable or create .env file")
  }
  
  cat("✅ OpenAI API key configured\n")
  return(api_key)
}

# Core API call function
call_openai_api <- function(prompt, system_message = NULL, config = AI_CONFIG) {
  api_key <- setup_openai_api()
  
  # Prepare messages
  messages <- list()
  if (!is.null(system_message)) {
    messages <- append(messages, list(list(role = "system", content = system_message)))
  }
  messages <- append(messages, list(list(role = "user", content = prompt)))
  
  # Prepare request body
  request_body <- list(
    model = config$model,
    messages = messages,
    max_tokens = config$max_tokens,
    temperature = config$temperature
  )
  
  # Make API request with retry logic
  for (attempt in 1:config$retry_attempts) {
    tryCatch({
      response <- POST(
        url = config$openai_api_url,
        add_headers(
          Authorization = paste("Bearer", api_key),
          "Content-Type" = "application/json"
        ),
        body = request_body,
        encode = "json",
        timeout(config$timeout)
      )
      
      if (response$status_code == 200) {
        result <- content(response, "parsed")
        return(result$choices[[1]]$message$content)
      } else {
        error_content <- content(response, "parsed")
        warning(paste("API request failed (attempt", attempt, "):", error_content$error$message))
        
        if (attempt == config$retry_attempts) {
          stop(paste("API request failed after", config$retry_attempts, "attempts"))
        }
        
        Sys.sleep(2^attempt)  # Exponential backoff
      }
    }, error = function(e) {
      if (attempt == config$retry_attempts) {
        stop(paste("API request error:", e$message))
      }
      warning(paste("API request error (attempt", attempt, "):", e$message))
      Sys.sleep(2^attempt)
    })
  }
}

# Prepare data for AI analysis
prepare_alert_data_for_ai <- function(alerts_data, summary_data) {
  
  data_summary <- list(
    total_alerts = nrow(alerts_data),
    alert_types = alerts_data %>%
      count(alert_type, sort = TRUE) %>%
      mutate(percentage = round(n / sum(n) * 100, 1)),
    
    risk_distribution = alerts_data %>%
      count(priority, sort = TRUE) %>%
      mutate(percentage = round(n / sum(n) * 100, 1)),
    
    top_risk_customers = alerts_data %>%
      group_by(customer_id) %>%
      summarise(
        total_alerts = n(),
        max_amount = max(amount, na.rm = TRUE),
        alert_types = paste(unique(alert_type), collapse = ", "),
        .groups = "drop"
      ) %>%
      arrange(desc(max_amount)) %>%
      head(10),
    
    financial_impact = list(
      total_amount = sum(alerts_data$amount, na.rm = TRUE),
      avg_alert_amount = mean(alerts_data$amount, na.rm = TRUE),
      high_risk_amount = sum(alerts_data$amount[alerts_data$priority == "HIGH"], na.rm = TRUE)
    ),
    
    key_statistics = summary_data
  )
  
  # Convert to readable text format
  formatted_summary <- paste(
    "AML ANALYSIS SUMMARY",
    "===================",
    paste("Total Alerts:", data_summary$total_alerts),
    paste("Alert Rate:", round((data_summary$total_alerts / 1296675) * 100, 3), "%"),
    paste("Customers Flagged:", length(unique(alerts_data$customer_id))),
    "",
    "ALERT TYPE BREAKDOWN:",
    paste(capture.output(print(data_summary$alert_types)), collapse = "\n"),
    "",
    "RISK PRIORITY DISTRIBUTION:",
    paste(capture.output(print(data_summary$risk_distribution)), collapse = "\n"),
    "",
    "TOP 5 HIGH-RISK CUSTOMERS:",
    paste(capture.output(print(head(data_summary$top_risk_customers, 5))), collapse = "\n"),
    "",
    "FINANCIAL IMPACT:",
    paste("Total Amount at Risk: $", format(round(data_summary$financial_impact$total_amount, 2), big.mark = ",")),
    paste("Average Alert Amount: $", format(round(data_summary$financial_impact$avg_alert_amount, 2), big.mark = ",")),
    paste("High-Risk Amount: $", format(round(data_summary$financial_impact$high_risk_amount, 2), big.mark = ",")),
    "",
    sep = "\n"
  )
  
  return(formatted_summary)
}

# Generate executive summary
generate_executive_summary <- function(alerts_data, summary_data, config = AI_CONFIG) {
  cat("🤖 Generating AI-powered executive summary...\n")
  
  # Prepare data for AI
  data_summary <- prepare_alert_data_for_ai(alerts_data, summary_data)
  
  # Create prompt
  prompt <- paste(
    config$prompts$executive_summary,
    "\n\nAML ANALYSIS DATA:\n",
    data_summary,
    "\n\nPlease provide a 4-paragraph executive summary covering:",
    "\n1. Key findings and overall risk assessment",
    "\n2. Most critical alerts requiring immediate attention",
    "\n3. Regulatory compliance implications and potential impact",
    "\n4. Recommended next steps and strategic priorities"
  )
  
  # Call OpenAI API
  summary <- call_openai_api(prompt, config = config)
  
  # Save summary
  executive_summary <- list(
    generated_date = Sys.POSIXct(Sys.time()),
    summary_type = "executive",
    content = summary,
    data_snapshot = data_summary
  )
  
  saveRDS(executive_summary, "outputs/reports/ai_executive_summary.rds")
  writeLines(summary, "outputs/reports/ai_executive_summary.txt")
  
  cat("✅ Executive summary generated and saved\n")
  return(executive_summary)
}

# Generate technical analysis
generate_technical_analysis <- function(alerts_data, summary_data, config = AI_CONFIG) {
  cat("🤖 Generating AI-powered technical analysis...\n")
  
  data_summary <- prepare_alert_data_for_ai(alerts_data, summary_data)
  
  prompt <- paste(
    config$prompts$technical_analysis,
    "\n\nAML ANALYSIS DATA:\n",
    data_summary,
    "\n\nPlease provide a detailed technical analysis covering:",
    "\n1. Detection algorithm performance and accuracy",
    "\n2. Pattern analysis and anomaly identification",
    "\n3. False positive analysis and optimization opportunities",
    "\n4. System performance metrics and recommendations"
  )
  
  analysis <- call_openai_api(prompt, config = config)
  
  technical_analysis <- list(
    generated_date = Sys.POSIXct(Sys.time()),
    summary_type = "technical",
    content = analysis,
    data_snapshot = data_summary
  )
  
  saveRDS(technical_analysis, "outputs/reports/ai_technical_analysis.rds")
  writeLines(analysis, "outputs/reports/ai_technical_analysis.txt")
  
  cat("✅ Technical analysis generated and saved\n")
  return(technical_analysis)
}

# Generate compliance report
generate_compliance_report <- function(alerts_data, summary_data, config = AI_CONFIG) {
  cat("🤖 Generating AI-powered compliance report...\n")
  
  data_summary <- prepare_alert_data_for_ai(alerts_data, summary_data)
  
  prompt <- paste(
    config$prompts$compliance_report,
    "\n\nAML ANALYSIS DATA:\n",
    data_summary,
    "\n\nPlease provide a comprehensive compliance report covering:",
    "\n1. Regulatory requirements adherence (BSA, FinCEN, etc.)",
    "\n2. Suspicious Activity Report (SAR) recommendations",
    "\n3. Control effectiveness assessment",
    "\n4. Compliance program enhancement recommendations"
  )
  
  report <- call_openai_api(prompt, config = config)
  
  compliance_report <- list(
    generated_date = Sys.POSIXct(Sys.time()),
    summary_type = "compliance",
    content = report,
    data_snapshot = data_summary
  )
  
  saveRDS(compliance_report, "outputs/reports/ai_compliance_report.rds")
  writeLines(report, "outputs/reports/ai_compliance_report.txt")
  
  cat("✅ Compliance report generated and saved\n")
  return(compliance_report)
}

# CUSTOMER RISK PROFILING SYSTEM
create_customer_risk_profile <- function(transaction_data, alerts_data) {
  cat("👥 Creating customer risk profiles...\n")
  
  # Calculate customer-level risk metrics
  customer_metrics <- transaction_data %>%
    group_by(customer_id) %>%
    summarise(
      total_transactions = n(),
      total_amount = sum(amt),
      avg_transaction_amount = mean(amt),
      max_transaction_amount = max(amt),
      min_transaction_amount = min(amt),
      std_transaction_amount = sd(amt),
      unique_merchants = n_distinct(merchant),
      unique_categories = n_distinct(category),
      unique_states = n_distinct(state),
      unique_cities = n_distinct(city),
      night_transactions = sum(is_night_transaction),
      weekend_transactions = sum(is_weekend),
      round_amount_transactions = sum(is_round_amount),
      high_amount_transactions = sum(is_high_amount),
      distant_transactions = sum(is_distant_transaction),
      transaction_span_days = as.numeric(max(transaction_date) - min(transaction_date)) + 1,
      first_transaction = min(transaction_date),
      last_transaction = max(transaction_date),
      avg_daily_transactions = total_transactions / transaction_span_days,
      avg_daily_amount = total_amount / transaction_span_days,
      .groups = "drop"
    )
  
  # Add alert information
  customer_alerts <- alerts_data %>%
    group_by(customer_id) %>%
    summarise(
      total_alerts = n(),
      max_amount = max(amount, na.rm = TRUE),
      avg_amount = mean(amount, na.rm = TRUE),
      alert_types = paste(unique(alert_type), collapse = ", "),
      high_priority_alerts = sum(priority == "HIGH"),
      medium_priority_alerts = sum(priority == "MEDIUM"),
      low_priority_alerts = sum(priority == "LOW"),
      .groups = "drop"
    )
  
  # Combine metrics and alerts
  customer_risk_profile <- customer_metrics %>%
    left_join(customer_alerts, by = "customer_id") %>%
    mutate(
      # Handle missing alert data
      total_alerts = ifelse(is.na(total_alerts), 0, total_alerts),
      max_amount = ifelse(is.na(max_amount), 0, max_amount),
      avg_amount = ifelse(is.na(avg_amount), 0, avg_amount),
      alert_types = ifelse(is.na(alert_types), "None", alert_types),
      high_priority_alerts = ifelse(is.na(high_priority_alerts), 0, high_priority_alerts),
      medium_priority_alerts = ifelse(is.na(medium_priority_alerts), 0, medium_priority_alerts),
      low_priority_alerts = ifelse(is.na(low_priority_alerts), 0, low_priority_alerts)
    ) %>%
    mutate(
      # Calculate comprehensive risk score components
      velocity_risk = pmin((avg_daily_transactions / 10) * 20, 25),  # Max 25 points
      amount_risk = pmin((total_amount / 50000) * 20, 25),          # Max 25 points
      pattern_risk = pmin((round_amount_transactions / 5) * 15, 25), # Max 25 points
      geographic_risk = pmin(unique_states * 5, 25),                # Max 25 points
      behavior_risk = pmin(
        (night_transactions / total_transactions * 100) * 0.3 +     # Night transaction rate
        (distant_transactions / total_transactions * 100) * 0.2,    # Distant transaction rate
        25
      ),
      
      # Comprehensive risk score (0-100)
      comprehensive_risk_score = velocity_risk + amount_risk + pattern_risk + 
                                geographic_risk + behavior_risk + 
                                pmin(total_alerts * 10, 25),  # Alert bonus
      
      # Risk category assignment
      risk_category = case_when(
        comprehensive_risk_score >= 80 ~ "CRITICAL",
        comprehensive_risk_score >= 60 ~ "HIGH",
        comprehensive_risk_score >= 40 ~ "MEDIUM",
        comprehensive_risk_score >= 20 ~ "LOW",
        TRUE ~ "MINIMAL"
      ),
      
      # Risk flags
      velocity_flag = avg_daily_transactions > 20,
      amount_flag = max_transaction_amount > 10000,
      geographic_flag = unique_states > 3,
      pattern_flag = round_amount_transactions > 10,
      night_activity_flag = (night_transactions / total_transactions) > 0.3,
      
      # Investigation priority
      investigation_priority = case_when(
        high_priority_alerts > 0 ~ "URGENT",
        total_alerts > 5 ~ "HIGH",
        total_alerts > 2 ~ "MEDIUM",
        total_alerts > 0 ~ "LOW",
        TRUE ~ "NONE"
      )
    ) %>%
    arrange(desc(comprehensive_risk_score))
  
  cat("✅ Customer risk profiles created for", nrow(customer_risk_profile), "customers\n")
  
  # Risk category summary
  risk_summary <- customer_risk_profile %>%
    count(risk_category) %>%
    mutate(percentage = round(n / sum(n) * 100, 1))
  
  cat("📊 Risk category distribution:\n")
  print(risk_summary)
  
  # Save risk profiles
  write_csv(customer_risk_profile, "outputs/alerts/customer_risk_profiles_level2.csv")
  
  return(customer_risk_profile)
}

# Time series analysis for patterns
create_time_series_analysis <- function(transaction_data, alerts_data) {
  cat("📈 Creating time series analysis...\n")
  
  # Daily transaction analysis
  daily_analysis <- transaction_data %>%
    group_by(transaction_date) %>%
    summarise(
      transaction_count = n(),
      total_amount = sum(amt),
      avg_amount = mean(amt),
      unique_customers = n_distinct(customer_id),
      unique_merchants = n_distinct(merchant),
      night_transactions = sum(is_night_transaction),
      high_amount_transactions = sum(is_high_amount),
      round_amount_transactions = sum(is_round_amount),
      .groups = "drop"
    ) %>%
    arrange(transaction_date)
  
  # Add alert information to daily analysis
  daily_alerts <- alerts_data %>%
    # Get transaction dates for customers (approximate)
    mutate(alert_date = as.Date(date)) %>%
    group_by(alert_date) %>%
    summarise(
      alert_count = n(),
      high_risk_alerts = sum(priority == "HIGH"),
      .groups = "drop"
    )
  
  # Combine daily metrics
  daily_combined <- daily_analysis %>%
    left_join(daily_alerts, by = c("transaction_date" = "alert_date")) %>%
    mutate(
      alert_count = ifelse(is.na(alert_count), 0, alert_count),
      high_risk_alerts = ifelse(is.na(high_risk_alerts), 0, high_risk_alerts),
      alert_rate = ifelse(transaction_count > 0, (alert_count / transaction_count) * 100, 0)
    )
  
  # Hourly pattern analysis
  hourly_analysis <- transaction_data %>%
    group_by(transaction_hour) %>%
    summarise(
      transaction_count = n(),
      avg_amount = mean(amt),
      unique_customers = n_distinct(customer_id),
      high_amount_transactions = sum(is_high_amount),
      .groups = "drop"
    )
  
  # Category analysis
  category_analysis <- transaction_data %>%
    group_by(category_clean) %>%
    summarise(
      transaction_count = n(),
      total_amount = sum(amt),
      avg_amount = mean(amt),
      unique_customers = n_distinct(customer_id),
      fraud_rate = mean(fraud_flag, na.rm = TRUE) * 100,
      .groups = "drop"
    ) %>%
    arrange(desc(transaction_count))
  
  # Save analysis
  write_csv(daily_combined, "outputs/alerts/daily_analysis_level2.csv")
  write_csv(hourly_analysis, "outputs/alerts/hourly_analysis.csv")
  write_csv(category_analysis, "outputs/alerts/category_analysis.csv")
  
  cat("✅ Time series analysis completed\n")
  
  return(list(
    daily_analysis = daily_combined,
    hourly_analysis = hourly_analysis,
    category_analysis = category_analysis
  ))
}

# Fallback text summaries (if AI fails)
generate_fallback_summaries <- function(alerts_data, summary_data) {
  cat("📋 Generating fallback text summaries...\n")
  
  fallback_executive <- paste(
    "EXECUTIVE SUMMARY - AML ANALYSIS",
    "================================",
    paste("Analysis Date:", Sys.Date()),
    paste("Total Alerts Generated:", nrow(alerts_data)),
    paste("High Priority Alerts:", sum(alerts_data$priority == "HIGH")),
    paste("Medium Priority Alerts:", sum(alerts_data$priority == "MEDIUM")),
    paste("Low Priority Alerts:", sum(alerts_data$priority == "LOW")),
    "",
    "KEY FINDINGS:",
    paste("- Detected", nrow(alerts_data), "suspicious transaction patterns"),
    paste("- Identified", length(unique(alerts_data$customer_id)), "customers requiring investigation"),
    paste("- Estimated financial impact: $", format(sum(alerts_data$amount, na.rm = TRUE), big.mark = ",")),
    "",
    "RECOMMENDATIONS:",
    "- Prioritize investigation of high-risk alerts",
    "- Review velocity patterns for potential automation",
    "- Investigate geographic anomalies for account takeover",
    "- Escalate structuring patterns to compliance team",
    "",
    sep = "\n"
  )
  
  writeLines(fallback_executive, "outputs/reports/fallback_executive_summary.txt")
  
  cat("✅ Fallback summaries generated\n")
  return(fallback_executive)
}

# Main AI integration function
main_ai_integration <- function() {
  cat("🚀 Starting Level 2: AI Integration\n")
  
  # Load Level 1 results
  if (file.exists("outputs/alerts/aml_alerts_level1.csv")) {
    alerts_data <- read_csv("outputs/alerts/aml_alerts_level1.csv")
    
    # Create summary data structure
    summary_data <- list(
      total_transactions = 1296675,
      total_alerts = nrow(alerts_data),
      alert_rate = round((nrow(alerts_data) / 1296675) * 100, 3),
      unique_customers_flagged = length(unique(alerts_data$customer_id))
    )
  } else {
    stop("❌ Level 1 outputs not found. Please complete Level 1 first.")
  }
  
  # Try AI analysis with fallback
  ai_results <- tryCatch({
    list(
      executive_summary = generate_executive_summary(alerts_data, summary_data),
      technical_analysis = generate_technical_analysis(alerts_data, summary_data),
      compliance_report = generate_compliance_report(alerts_data, summary_data)
    )
  }, error = function(e) {
    cat("❌ AI analysis failed:", e$message, "\n")
    cat("💡 Generating fallback summaries...\n")
    
    list(
      error = TRUE,
      message = e$message,
      fallback_summary = generate_fallback_summaries(alerts_data, summary_data)
    )
  })
  
  cat("✅ Level 2 AI integration completed!\n")
  return(ai_results)
}

# Test AI integration
if (!exists("ai_integration_results")) {
  # ai_integration_results <- main_ai_integration()
  cat("🎯 Run ai_integration_results <- main_ai_integration() to execute\n")
}