#!/bin/bash
set -e

# ==============================================================================
# 0. FETCH CONFIGURATION AND SECRETS
# ==============================================================================
CERT_DIR="/home/chronos/letsencrypt"
MOVIES_DIR="/home/chronos/movies"
NETWORK_NAME="movie-night-net"
WEBHOOK_IMAGE_NAME="ghcr.io/axisofentropy/movie-night-webhook:latest"

echo "--- Fetching Configuration and Secrets ---"
# First, get an auth token from the metadata server
GCP_PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | grep -o '"access_token": *"[^"]*"' | cut -d'"' -f4)

DOMAIN_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/domain-name)
HOSTNAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/hostname)
DOMAIN="${HOSTNAME}.${DOMAIN_NAME}"

# Function to fetch a secret from Secret Manager
fetch_secret() {
  local project_id="$1"
  local secret_name="$2"
  curl -s -H "Authorization: Bearer ${TOKEN}" \
    "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${secret_name}/versions/latest:access" \
  | grep -o '"data": *"[^"]*"' | cut -d'"' -f4 | base64 -d
}

# Fetch the actual secrets
GDAPIKEY=$(fetch_secret "${GCP_PROJECT_ID}" "godaddy-api-key")
SECRET_TOKEN=$(fetch_secret "${GCP_PROJECT_ID}" "webhook-secret-token")

# ==============================================================================
# 1. DYNAMIC DNS AND CERTIFICATE
# ==============================================================================
echo "--- Starting Dynamic DNS Check ---"
MYDOMAIN="${DOMAIN_NAME}"
MYHOSTNAME="${HOSTNAME}"

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

echo "--- Generating a new TLS Certificate with Certbot for ${DOMAIN} ---"
mkdir -p "${CERT_DIR}"

docker run --rm \
  -p 80:80 \
  -v "${CERT_DIR}:/etc/letsencrypt" \
  certbot/certbot certonly --standalone \
  --non-interactive --agree-tos --register-unsafely-without-email \
  -d "${DOMAIN}"

echo "Certificate generated successfully."

# ==============================================================================
# 2. CONTAINER CONFIGURATION & DEPLOYMENT
# ==============================================================================

mkdir -p "${MOVIES_DIR}"
chown chronos:chronos "${MOVIES_DIR}"
echo "--- Cleaning up old containers and networks ---"
docker stop mediamtx webhook-server || true
docker rm mediamtx webhook-server || true
docker network rm ${NETWORK_NAME} || true
docker network create ${NETWORK_NAME}

echo "--- Pulling latest images ---"
docker pull "${WEBHOOK_IMAGE_NAME}"
docker pull bluenviron/mediamtx:latest-ffmpeg

echo "--- Launching Mediamtx Container ---"
docker run -d --restart=always \
  --name mediamtx \
  --network ${NETWORK_NAME} \
  -p 8554:8554 -p 1935:1935 -p 8888:8888 -p 8889:8889 -p 9997:9997 \
  bluenviron/mediamtx:latest-ffmpeg

echo "--- Launching Webhook Server ---"
docker run -d --restart=always \
  --name webhook-server \
  --network ${NETWORK_NAME} \
  -p 443:443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${MOVIES_DIR}:/downloads" \
  -v "${CERT_DIR}:/certs:ro" \
  -e SECRET_TOKEN="${SECRET_TOKEN}" \
  -e MOVIES_DIR="${MOVIES_DIR}" \
  -e DOMAIN="${DOMAIN}" \
  "${WEBHOOK_IMAGE_NAME}"

echo "--- All containers are starting. Deployment complete! ---"