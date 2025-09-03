# Use a slim, secure base image
FROM python:3.9-slim

WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code and the new entrypoint script
COPY app.py .
COPY blueprints/ ./blueprints/
COPY entrypoint.sh /entrypoint.sh

# Make the entrypoint script executable
RUN chmod +x /entrypoint.sh

# Expose the HTTPS port
EXPOSE 443

# Set the entrypoint and the default command
ENTRYPOINT ["/entrypoint.sh"]
CMD ["app:app"]