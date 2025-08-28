import os
import requests
from flask import Blueprint, request, current_app, abort, jsonify
from functools import wraps

movie_api_blueprint = Blueprint('movie_api', __name__)

# --- Helper Function ---
def format_bytes(size_bytes):
    """Converts bytes to a human-readable string (KB, MB, GB)."""
    if size_bytes == 0:
        return "0 B"
    power = 1024
    i = 0
    p = ["B", "KB", "MB", "GB", "TB"]
    while size_bytes > power:
        size_bytes /= power
        i += 1
    return f"{size_bytes:.2f} {p[i]}"

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
@movie_api_blueprint.route('/download', methods=['POST'])
@require_token
def download_movie():
    """
    Webhook to download a movie.
    Accepts JSON: {"url": "...", "filename": "movie.mp4" (optional)}
    Returns the final filename and size.
    """
    if not request.json or 'url' not in request.json:
        abort(400, description="Bad Request: JSON body with a 'url' key is required.")

    movie_url = request.json['url']
    # Use the provided filename or default to 'current_movie.mp4'
    filename = request.json.get('filename', 'current_movie.mp4')
    output_path = f"/downloads/{filename}"

    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    
    try:
        print(f"Starting download from {movie_url} to {output_path}...")
        with requests.get(movie_url, stream=True, headers=headers, allow_redirects=True) as r:
            r.raise_for_status()
            with open(output_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192): 
                    f.write(chunk)
        
        file_size_bytes = os.path.getsize(output_path)
        human_readable_size = format_bytes(file_size_bytes)
        
        print(f"Download finished. Size: {human_readable_size}")
        return jsonify(
            status="success",
            message="Download complete.",
            filename=filename,
            fileSize=human_readable_size
        ), 200

    except requests.exceptions.RequestException as e:
        return jsonify(status="error", message="Download failed.", details=str(e)), 500

@movie_api_blueprint.route('/start/<path_name>', methods=['POST'])
@require_token
def start_stream(path_name):
    """
    Configures a mediamtx path to start a stream from a specific movie file.
    Accepts JSON: {"filename": "movie.mp4"}
    Returns the HLS and RTSP URLs for clients.
    """
    if not request.json or 'filename' not in request.json:
        abort(400, description="Bad Request: JSON body with a 'filename' key is required.")

    filename = request.json['filename']
    movie_path_in_mediamtx = f"/movies/{filename}"
    
    if not os.path.exists(f"/downloads/{filename}"):
        return jsonify(status="error", message=f"Movie file not found: {filename}. Please download it first."), 404

    ffmpeg_command = (
        f"ffmpeg -re -i {movie_path_in_mediamtx}"
        " -c:v copy -c:a copy"
        f" -f rtsp -rtsp_transport tcp rtsp://admin:admin@mediamtx:8554/{path_name}"
    )

    config_payload = { "runOnInit": ffmpeg_command }

    try:
        mediamtx_api_url = f"http://mediamtx:9997/v3/config/paths/replace/{path_name}"
        response = requests.post(mediamtx_api_url, json=config_payload, auth=('admin', 'admin'))
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