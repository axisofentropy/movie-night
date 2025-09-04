import os
import requests
from flask import Blueprint, request, current_app, abort, jsonify
from functools import wraps
from werkzeug.utils import secure_filename
from urllib.parse import urlparse

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
    # --- Input Sanitization ---
    # 1. Sanitize path_name to prevent path traversal attacks.
    sane_path_name = secure_filename(path_name)
    if not sane_path_name:
        abort(400, description="Bad Request: Invalid path_name.")

    # 2. Validate the movie URL to ensure it's a valid URL.
    if not request.json or 'url' not in request.json:
        abort(400, description="Bad Request: JSON body with a 'url' key is required.")
    
    movie_url = request.json['url']
    parsed_url = urlparse(movie_url)
    if not all([parsed_url.scheme in ['http', 'https'], parsed_url.netloc]):
        abort(400, description="Bad Request: Invalid or non-HTTP(S) URL provided.")

    # This command uses ffmpeg's internal HTTP client to stream directly from the URL.
    # This is more memory-efficient and robust than piping from wget or curl.
    # - `ffmpeg -re -i "{movie_url}"`: Reads from the URL at the native frame rate (-re).
    # - The rest of the command copies the video/audio streams and pushes them to mediamtx via RTSP.
    ffmpeg_command = (
        f"ffmpeg -re -i \"{movie_url}\""
        " -c:v copy -c:a copy"
        f" -f rtsp -rtsp_transport tcp rtsp://admin:admin@mediamtx:8554/{sane_path_name}"
    )

    config_payload = { "runOnDemand": ffmpeg_command }

    mediamtx_user = os.environ.get("MEDIAMTX_API_USER", "admin")
    mediamtx_pass = os.environ.get("MEDIAMTX_API_PASS", "admin")
    mediamtx_host = os.environ.get("MEDIAMTX_API_HOST", "mediamtx")

    try:
        mediamtx_api_url = f"http://{mediamtx_host}:9997/v3/config/paths/replace/{sane_path_name}"
        response = requests.post(mediamtx_api_url, json=config_payload, auth=(mediamtx_user, mediamtx_pass))
        response.raise_for_status()

        domain = os.environ.get("DOMAIN")
        hls_url = f"https://{domain}/{sane_path_name}/"
        rtsp_url = f"rtsp://{domain}:8554/{sane_path_name}"

        return jsonify(
            status="success",
            message=f"Stream '{sane_path_name}' is configured and starting.",
            hlsUrl=hls_url,
            rtspUrl=rtsp_url
        ), 200

    except requests.exceptions.RequestException as e:
        return jsonify(status="error", message="Failed to configure mediamtx.", details=str(e)), 500
