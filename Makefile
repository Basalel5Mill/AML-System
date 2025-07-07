# AML System Makefile
# Provides easy commands for building and running Go applications

.PHONY: build upload monitor run clean test deps help

# Variables
BINARY_DIR=bin
UPLOAD_BINARY=$(BINARY_DIR)/upload
MONITOR_BINARY=$(BINARY_DIR)/monitor

# Default target
help:
	@echo "🏦 AML System - Available Commands:"
	@echo "=================================="
	@echo "  deps     - Download Go dependencies"
	@echo "  build    - Build all binaries"
	@echo "  upload   - Run CSV upload tool"
	@echo "  monitor  - Run real-time monitoring"
	@echo "  clean    - Clean build artifacts"
	@echo "  test     - Run tests"
	@echo ""
	@echo "Usage Examples:"
	@echo "  make upload CSV=transactions.csv"
	@echo "  make monitor"

# Download dependencies
deps:
	@echo "📦 Downloading Go dependencies..."
	go mod download
	go mod tidy

# Build all binaries
build: deps
	@echo "🔨 Building AML system binaries..."
	@mkdir -p $(BINARY_DIR)
	@echo "Building upload tool..."
	go build -o $(UPLOAD_BINARY) ./cmd/upload
	@echo "Building monitor tool..."
	go build -o $(MONITOR_BINARY) ./cmd/monitor
	@echo "✅ Build complete!"

# Upload CSV and trigger processing
upload: build
	@echo "📤 Running CSV upload and processing..."
	@if [ -n "$(CSV)" ]; then \
		./$(UPLOAD_BINARY) $(CSV); \
	else \
		./$(UPLOAD_BINARY); \
	fi

# Run real-time monitor
monitor: build
	@echo "🔍 Starting real-time AML monitor..."
	./$(MONITOR_BINARY)

# Run upload directly with Go (for development)
run-upload:
	@echo "📤 Running upload tool (development mode)..."
	@if [ -n "$(CSV)" ]; then \
		go run ./cmd/upload $(CSV); \
	else \
		go run ./cmd/upload; \
	fi

# Run monitor directly with Go (for development)
run-monitor:
	@echo "🔍 Running monitor (development mode)..."
	go run ./cmd/monitor

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf $(BINARY_DIR)
	go clean

# Run tests
test:
	@echo "🧪 Running tests..."
	go test ./...

# Install system globally (optional)
install: build
	@echo "📦 Installing AML tools globally..."
	sudo cp $(UPLOAD_BINARY) /usr/local/bin/aml-upload
	sudo cp $(MONITOR_BINARY) /usr/local/bin/aml-monitor
	@echo "✅ Installed to /usr/local/bin/"
	@echo "You can now run: aml-upload or aml-monitor"

# Build for multiple platforms
build-all: deps
	@echo "🌍 Building for multiple platforms..."
	@mkdir -p $(BINARY_DIR)
	
	# Linux
	GOOS=linux GOARCH=amd64 go build -o $(BINARY_DIR)/upload-linux ./cmd/upload
	GOOS=linux GOARCH=amd64 go build -o $(BINARY_DIR)/monitor-linux ./cmd/monitor
	
	# macOS
	GOOS=darwin GOARCH=amd64 go build -o $(BINARY_DIR)/upload-mac ./cmd/upload
	GOOS=darwin GOARCH=amd64 go build -o $(BINARY_DIR)/monitor-mac ./cmd/monitor
	
	# Windows
	GOOS=windows GOARCH=amd64 go build -o $(BINARY_DIR)/upload.exe ./cmd/upload
	GOOS=windows GOARCH=amd64 go build -o $(BINARY_DIR)/monitor.exe ./cmd/monitor
	
	@echo "✅ Multi-platform build complete!"

# Quick start - setup everything
setup: deps build
	@echo "🚀 AML System Setup Complete!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Upload data:     make upload CSV=your_file.csv"
	@echo "2. Start monitor:   make monitor"
	@echo "3. Check dashboard: Open R Shiny app"

# Development watch mode (requires entr)
watch:
	@echo "👀 Watching for changes... (requires 'entr' tool)"
	find . -name "*.go" | entr -r make run-upload