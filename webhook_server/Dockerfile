# Use a slim, secure base image
FROM registry.os.wiz.io/python:3.14

WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Remove shell and package manager for production
RUN apk del wizos-keys wizos-apk-auth apk-tools

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
