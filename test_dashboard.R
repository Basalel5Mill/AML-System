# Simple test to run the AML dashboard
library(shiny)

cat("🚀 Starting AML Dashboard Test...\n")
cat("📊 Dashboard will start on port 8080\n")
cat("🌐 Open browser to: http://localhost:8080\n\n")

# Run the dashboard on a different port
runApp(".", port = 8080, host = "127.0.0.1", launch.browser = TRUE)