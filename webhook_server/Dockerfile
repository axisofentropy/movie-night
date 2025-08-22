# Use a slim, secure base image
FROM python:3.9-slim

WORKDIR /app

# Create directories for downloads
RUN mkdir /downloads

# Copy and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code and scripts
COPY app.py .
COPY blueprints/ ./blueprints/

# Expose the port the app runs on
EXPOSE 5000

# Set the command to run the application
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]