# Use the official R base image
FROM r-base:4.3.1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    sudo \
    gdebi-core \
    pandoc \
    libcurl4-gnutls-dev \
    libcairo2-dev \
    libxt-dev \
    libssl-dev \
    libssh2-1-dev \
    libxml2-dev \
    libv8-dev \
    libsodium-dev \
    libsecret-1-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgit2-dev \
    && rm -rf /var/lib/apt/lists/*

# Install R packages based on your app.R dependencies
RUN R -e "install.packages(c('shiny', 'shinydashboard', 'DT', 'htmltools', 'bigrquery', 'DBI', 'dplyr', 'ggplot2', 'plotly', 'lubridate', 'stringr', 'tidyr', 'jsonlite', 'httr'), repos='https://cloud.r-project.org/')"

# Create app directory
WORKDIR /app

# Copy application files
COPY app.R .
COPY app_professional.R .
COPY run_professional_dashboard.R .
COPY .env .

# Copy data and output directories if they exist
COPY data/ data/
COPY outputs/ outputs/

# Create necessary directories
RUN mkdir -p outputs/alerts outputs/reports outputs/models

# Expose port
EXPOSE 8080

# Set environment variables
ENV PORT=8080
ENV GOOGLE_CLOUD_PROJECT=anlaytics-465216

# Run the professional application
CMD ["R", "-e", "shiny::runApp('app_professional.R', host='0.0.0.0', port=as.numeric(Sys.getenv('PORT', '8080')))"]