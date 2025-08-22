#!/bin/bash
set -e

# ==============================================================================
# 0. FETCH SECRETS
# ==============================================================================
echo "--- Fetching Secrets ---"
# First, get an auth token from the metadata server
TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | grep -o '"access_token": *"[^"]*"' | cut -d'"' -f4)

# Function to fetch a secret from Secret Manager
fetch_secret() {
  local project_id="$1"
  local secret_name="$2"
  curl -s -H "Authorization: Bearer ${TOKEN}" \
    "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${secret_name}/versions/latest:access" \
  | grep -o '"data": *"[^"]*"' | cut -d'"' -f4 | base64 -d
}

# Fetch the actual secrets
GCP_PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
GDAPIKEY=$(fetch_secret "${GCP_PROJECT_ID}" "godaddy-api-key")
SECRET_TOKEN=$(fetch_secret "${GCP_PROJECT_ID}" "webhook-secret-token")

# ==============================================================================
# 1. DYNAMIC DNS CONFIGURATION
# ==============================================================================
echo "--- Starting Dynamic DNS Check ---"
MYDOMAIN="axisofentropy.net"
MYHOSTNAME="movienight"

MYIP=$(curl -s "https://api.ipify.org")
DNSDATA=$(curl -s -X GET -H "Authorization: sso-key ${GDAPIKEY}" "https://api.godaddy.com/v1/domains/${MYDOMAIN}/records/A/${MYHOSTNAME}")
GDIP=$(echo "$DNSDATA" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")

if [[ "$GDIP" != "$MYIP" && -n "$MYIP" ]]; then
  echo "IP has changed. Updating GoDaddy DNS record..."
  curl -s -X PUT "https://api.godaddy.com/v1/domains/${MYDOMAIN}/records/A/${MYHOSTNAME}" \
    -H "Authorization: sso-key ${GDAPIKEY}" \
    -H "Content-Type: application/json" \
    -d "[{\"data\": \"${MYIP}\"}]"
fi
echo "--- Dynamic DNS Check Complete ---"

# ==============================================================================
# 2. CONFIGURATION & DEPLOYMENT
# ==============================================================================
MOVIES_DIR="/home/chronos/movies"
NETWORK_NAME="movie-night-net"
WEBHOOK_IMAGE_NAME="ghcr.io/axisofentropy/movie-night-webhook:latest"

mkdir -p "${MOVIES_DIR}"
chown chronos:chronos "${MOVIES_DIR}"

docker network create ${NETWORK_NAME} || true
docker pull "${WEBHOOK_IMAGE_NAME}"
docker pull bluenviron/mediamtx:latest-ffmpeg

docker run -d --restart=always \
  --name mediamtx \
  --network ${NETWORK_NAME} \
  -p 8554:8554 -p 1935:1935 -p 8888:8888 -p 8889:8889 -p 9997:9997 \
  bluenviron/mediamtx:latest-ffmpeg

docker run -d --restart=always \
  --name webhook-server \
  --network ${NETWORK_NAME} \
  -p 5000:5000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${MOVIES_DIR}:/downloads" \
  -e SECRET_TOKEN="${SECRET_TOKEN}" \
  -e MOVIES_DIR="${MOVIES_DIR}" \
  "${WEBHOOK_IMAGE_NAME}"

echo "--- All containers are starting. Deployment complete! ---"