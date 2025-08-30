#!/bin/bash
set -e
# set -x # show everything for debugging. then rotate your keys!

# ==============================================================================
# 0. FETCH CONFIGURATION AND SECRETS
# ==============================================================================
CERT_DIR="/home/chronos/letsencrypt"
MOVIES_DIR="/home/chronos/movies"
MEDIAMTX_CONFIG_DIR="/home/chronos/mediamtx"

NETWORK_NAME="movie-night-net"
WEBHOOK_IMAGE_NAME="ghcr.io/axisofentropy/movie-night-webhook:latest"
STARTUP_BUCKET_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/startup-script-url | cut -d'/' -f3)

echo "--- Fetching Configuration and Secrets ---"
# First, get an auth token from the metadata server
GCP_PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | grep -o '"access_token": *"[^"]*"' | cut -d'"' -f4)

DOMAIN_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/domain-name)
HOSTNAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/hostname)
DNS_ZONE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/dns-zone-name)
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
SECRET_TOKEN=$(fetch_secret "${GCP_PROJECT_ID}" "webhook-secret-token")

# ==============================================================================
# 1. DYNAMIC DNS (using Cloud DNS)
# ==============================================================================
echo "--- Starting Cloud DNS Update Check ---"
MYIP=$(curl -s "https://api.ipify.org")
RESOLVED_IP=$(curl -s "https://dns.google/resolve?name=${DOMAIN}&type=A" | grep -oE '"data":"(\b([0-9]{1,3}\.){3}[0-9]{1,3}\b)"' | cut -d'"' -f4 | head -n 1)

if [[ "${RESOLVED_IP}" != "${MYIP}" && -n "${MYIP}" ]]; then
  echo "DNS IP ${RESOLVED_IP} does not match VM IP ${MYIP}. Updating Cloud DNS..."
  
  # Note the trailing dot on the domain name for the API
  RECORD_NAME="${DOMAIN}."
  
  # Construct the API request body
  JSON_BODY=$(cat <<EOM
{
  "additions": [
    {
      "name": "${RECORD_NAME}",
      "type": "A",
      "ttl": 60,
      "rrdatas": ["${MYIP}"]
    }
  ],
  "deletions": [
    {
      "name": "${RECORD_NAME}",
      "type": "A",
      "ttl": 60,
      "rrdatas": ["${RESOLVED_IP}"]
    }
  ]
}
EOM
)
  echo "${JSON_BODY}"

  # Call the Cloud DNS API to patch the record set
  curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    --data "${JSON_BODY}" \
    "https://dns.googleapis.com/dns/v1/projects/${GCP_PROJECT_ID}/managedZones/${DNS_ZONE_NAME}/changes"

  echo "Cloud DNS update request sent. Waiting for propagation..."
  # The DNS propagation check from the previous script is still valid here
  sleep 10 # Simple wait, or re-add the propagation loop if needed
else
  echo "DNS IP ${RESOLVED_IP} already matches VM IP ${MYIP}. No update needed."
fi
echo "--- Cloud DNS Update Complete ---"

echo "--- Generating a new TLS Certificate with Certbot for ${DOMAIN} ---"
mkdir -p "${CERT_DIR}"

TIMEOUT=300
INTERVAL=15
END_TIME=$(( $(date +%s) + TIMEOUT ))
CERTBOT_SUCCESS=false

docker pull --quiet certbot/certbot
while [[ $(date +%s) -lt $END_TIME ]]; do
  # Attempt to generate the certificate
  if docker run --rm \
    -p 80:80 \
    -v "${CERT_DIR}:/etc/letsencrypt" \
    certbot/certbot certonly --standalone \
    --non-interactive --agree-tos --register-unsafely-without-email \
    -d "${DOMAIN}"; then
    
    echo "Certificate generated successfully."
    CERTBOT_SUCCESS=true
    break # Exit the loop on success
  else
    echo "Certbot failed. Retrying in ${INTERVAL} seconds..."
    sleep "${INTERVAL}"
  fi
done

if [[ "${CERTBOT_SUCCESS}" != "true" ]]; then
  echo "FATAL: Failed to generate certificate after ${TIMEOUT} seconds."
  exit 1
fi

# ==============================================================================
# 2. CONTAINER CONFIGURATION & DEPLOYMENT
# ==============================================================================

mkdir -p "${MOVIES_DIR}"
mkdir -p "${MEDIAMTX_CONFIG_DIR}"
chown chronos:chronos "${MOVIES_DIR}"
# chown --recursive chronos:chronos "${CERT_DIR}"

echo "--- Cleaning up old containers and networks ---"
docker stop mediamtx webhook-server || true
docker rm mediamtx webhook-server || true
docker network rm ${NETWORK_NAME} || true
docker network create ${NETWORK_NAME}

# Download the mediamtx config file using curl and the Storage JSON API
echo "--- Downloading mediamtx configuration ---"
curl -s -X GET \
  -H "Authorization: Bearer ${TOKEN}" \
  -o "${MEDIAMTX_CONFIG_DIR}/mediamtx.yml" \
  "https://storage.googleapis.com/storage/v1/b/${STARTUP_BUCKET_NAME}/o/mediamtx.yml?alt=media"

# Download the snipe movie file
echo "--- Downloading snipe movie ---"
curl -s -X GET \
  -H "Authorization: Bearer ${TOKEN}" \
  -o "${MOVIES_DIR}/snipe.mp4" \
  "https://storage.googleapis.com/storage/v1/b/${STARTUP_BUCKET_NAME}/o/snipe.mp4?alt=media"

# Set sample movie permissions to read-only for all
chmod 444 "${MOVIES_DIR}/snipe.mp4"

echo "--- Pulling latest images ---"
docker pull --quiet "${WEBHOOK_IMAGE_NAME}"
docker pull --quiet bluenviron/mediamtx:latest-ffmpeg

echo "--- Launching Mediamtx Container ---"
docker run -d --restart=always \
  --name mediamtx \
  --network ${NETWORK_NAME} \
  -p 443:443 -p 8554:8554 -p 1935:1935 -p 8889:8889 -p 9997:9997 \
  -v "${MEDIAMTX_CONFIG_DIR}/mediamtx.yml:/mediamtx.yml:ro" \
  -v "${MOVIES_DIR}:/movies:ro" \
  -v "${CERT_DIR}:/certs:ro" \
  -e MTX_HLSSERVERKEY="/certs/live/${DOMAIN}/privkey.pem" \
  -e MTX_HLSSERVERCERT="/certs/live/${DOMAIN}/fullchain.pem" \
  bluenviron/mediamtx:latest-ffmpeg

echo "--- Launching Webhook Server ---"
docker run -d --restart=always \
  --name webhook-server \
  --network ${NETWORK_NAME} \
  -p 4443:443 \
  -v "${MOVIES_DIR}:/downloads" \
  -v "${CERT_DIR}:/certs:ro" \
  -e SECRET_TOKEN="${SECRET_TOKEN}" \
  -e MOVIES_DIR="${MOVIES_DIR}" \
  -e DOMAIN="${DOMAIN}" \
  "${WEBHOOK_IMAGE_NAME}"

echo "--- All containers are starting. Deployment complete! ---"