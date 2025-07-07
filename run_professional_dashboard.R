# Quick launcher for Professional AML Dashboard
library(shiny)

cat("🏦 Launching Professional AML Dashboard\n")
cat("🎨 Dark theme with off-white accents\n")
cat("🚀 Starting on port 8080...\n\n")

# Kill any existing process on port 8080
system("lsof -ti:8080 | xargs kill -9 2>/dev/null", ignore.stderr = TRUE)

# Start the professional dashboard
runApp("app_professional.R", port = 8080, host = "127.0.0.1", launch.browser = TRUE)