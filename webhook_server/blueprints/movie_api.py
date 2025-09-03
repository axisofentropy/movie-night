import os
import requests
from flask import Blueprint, request, current_app, abort, jsonify
from functools import wraps

movie_api_blueprint = Blueprint('movie_api', __name__)

# --- Security Decorator ---
def require_token(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('X-Auth-Token')
        if not token or token != current_app.config['SECRET_TOKEN']:
            abort(401, description="Unauthorized: Invalid or missing token.")
        return f(*args, **kwargs)
    return decorated_function

# --- Webhook Routes ---
@movie_api_blueprint.route('/start/<path_name>', methods=['POST'])
@require_token
def start_stream(path_name):
    """
    Configures a mediamtx path to start streaming a movie directly from a URL.
    Accepts JSON: {"url": "..."}
    Returns the HLS and RTSP URLs for clients.
    """
    if not request.json or 'url' not in request.json:
        abort(400, description="Bad Request: JSON body with a 'url' key is required.")

    movie_url = request.json['url']

    # This command uses curl to download the movie and pipes it directly to ffmpeg.
    # - `curl -L -s "{movie_url}"`: Downloads from the URL, follows redirects (-L), and is silent (-s).
    # - `ffmpeg -re -i pipe:0`: Tells ffmpeg to read from stdin at the native frame rate (-re).
    # - The rest of the command copies the video/audio streams and pushes them to mediamtx via RTSP.
    ffmpeg_command = (
        f"curl -L -s \"{movie_url}\" | ffmpeg -re -i pipe:0"
        " -c:v copy -c:a copy"
        f" -f rtsp -rtsp_transport tcp rtsp://admin:admin@mediamtx:8554/{path_name}"
    )

    config_payload = { "runOnDemand": ffmpeg_command }

    mediamtx_user = os.environ.get("MEDIAMTX_API_USER", "admin")
    mediamtx_pass = os.environ.get("MEDIAMTX_API_PASS", "admin")
    mediamtx_host = os.environ.get("MEDIAMTX_API_HOST", "mediamtx")

    try:
        mediamtx_api_url = f"http://{mediamtx_host}:9997/v3/config/paths/replace/{path_name}"
        response = requests.post(mediamtx_api_url, json=config_payload, auth=(mediamtx_user, mediamtx_pass))
        response.raise_for_status()

        domain = os.environ.get("DOMAIN")
        hls_url = f"https://{domain}/{path_name}/"
        rtsp_url = f"rtsp://{domain}:8554/{path_name}"

        return jsonify(
            status="success",
            message=f"Stream '{path_name}' is configured and starting.",
            hlsUrl=hls_url,
            rtspUrl=rtsp_url
        ), 200

    except requests.exceptions.RequestException as e:
        return jsonify(status="error", message="Failed to configure mediamtx.", details=str(e)), 500