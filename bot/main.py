import os
from flask import Flask, request, jsonify
from nacl.signing import VerifyKey
from nacl.exceptions import BadSignatureError
import requests

app = Flask(__name__)

# Load secrets from environment variables (mounted from Secret Manager)
BOT_PUBLIC_KEY = os.environ.get("BOT_PUBLIC_KEY")
WEBHOOK_SECRET_TOKEN = os.environ.get("WEBHOOK_SECRET_TOKEN")
GCE_WEBHOOK_URL = os.environ.get("GCE_WEBHOOK_URL") # e.g., https://movienight.axisofentropy.net:4443

verify_key = VerifyKey(bytes.fromhex(BOT_PUBLIC_KEY))

@app.route("/interactions", methods=["POST"])
def interactions():
    # 1. Verify all incoming requests from Discord
    signature = request.headers.get("X-Signature-Ed25519")
    timestamp = request.headers.get("X-Signature-Timestamp")
    body = request.data.decode("utf-8")

    try:
        verify_key.verify(f"{timestamp}{body}".encode(), bytes.fromhex(signature))
    except BadSignatureError:
        return "Invalid request signature", 401

    # 2. Handle Discord's PING to check if the endpoint is alive
    interaction = request.json
    if interaction["type"] == 1: # PING
        return jsonify({"type": 1}) # PONG

    # 3. Handle slash commands
    if interaction["type"] == 2: # APPLICATION_COMMAND
        command_name = interaction["data"]["name"]
        
        if command_name == "download":
            return handle_download(interaction)
        elif command_name == "start":
            return handle_start(interaction)

    return "OK", 200

def handle_download(interaction):
    # A more robust way to get options: by name
    options = {opt['name']: opt['value'] for opt in interaction['data']['options']}
    url = options.get('url')
    filename = options.get('filename')

    api_response = requests.post(
        f"{GCE_WEBHOOK_URL}/movie/download",
        headers={"X-Auth-Token": WEBHOOK_SECRET_TOKEN},
        json={"url": url, "filename": filename},
        # verify=False # Use verify=False if your GCE VM has a self-signed or unrecognized cert
    )
    
    if api_response.status_code == 200:
        data = api_response.json()
        content = f"✅ **Download complete!**\nFile: `{data['filename']}`\nSize: **{data['fileSize']}**"
    else:
        content = f"❌ **Error downloading:**\n`{api_response.text}`"

    return jsonify({"type": 4, "data": {"content": content}})

def handle_start(interaction):
    # A more robust way to get options: by name
    options = {opt['name']: opt['value'] for opt in interaction['data']['options']}
    path_name = options.get('path_name')
    filename = options.get('filename')

    api_response = requests.post(
        f"{GCE_WEBHOOK_URL}/movie/start/{path_name}",
        headers={"X-Auth-Token": WEBHOOK_SECRET_TOKEN},
        json={"filename": filename},
        # verify=False
    )

    if api_response.status_code == 200:
        data = api_response.json()
        content = f"🎬 **Stream is configured!**\nWatch here: {data['hlsUrl']}"
    else:
        content = f"❌ **Error starting stream:**\n`{api_response.text}`"
        
    return jsonify({"type": 4, "data": {"content": content}})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))