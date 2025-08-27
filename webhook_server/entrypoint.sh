#!/bin/sh
set -e

# This script is the container's entrypoint. It reads the DOMAIN environment
# variable and then uses it to start gunicorn with the correct cert paths.

# The "$@" at the end passes any arguments from the Dockerfile's CMD
# to gunicorn, in this case "app:app".
exec gunicorn \
    --bind "0.0.0.0:443" \
    --timeout 300 \
    --certfile="/certs/live/${DOMAIN}/fullchain.pem" \
    --keyfile="/certs/live/${DOMAIN}/privkey.pem" \
    "$@"