# Use a slim, secure base image
FROM python:3.9-slim

WORKDIR /app

# Create directories for scripts and downloads
RUN mkdir /scripts
RUN mkdir /downloads

# Copy and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code and scripts
COPY app.py .
COPY blueprints/ ./blueprints/
COPY scripts/ /scripts/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Expose the port the app runs on
EXPOSE 5000

# Set the command to run the application
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]