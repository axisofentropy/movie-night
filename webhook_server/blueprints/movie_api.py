import os
import subprocess
from functools import wraps
from flask import Blueprint, request, current_app, abort, jsonify
import requests

# ... (Blueprint object and require_token decorator are the same) ...
movie_api_blueprint = Blueprint('movie_api', __name__)

def require_token(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = request.headers.get('X-Auth-Token')
        if not token or token != current_app.config['SECRET_TOKEN']:
            abort(401, description="Unauthorized: Invalid or missing token.")
        return f(*args, **kwargs)
    return decorated_function

# ... (download_movie function is the same) ...
@movie_api_blueprint.route('/download', methods=['POST'])
@require_token
def download_movie():
    movie_url = request.data.decode('utf-8')
    if not movie_url:
        abort(400, description="Bad Request: The request body cannot be empty.")
    output_path = "/downloads/current_movie.mp4"

    # NEW: Define a common User-Agent header to mimic a browser.
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }

    try:
        with requests.get(movie_url, stream=True, headers=headers, allow_redirects=True) as r:
            r.raise_for_status()
            with open(output_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192): 
                    f.write(chunk)
        print(f"Download finished. File saved to {output_path}")
        return jsonify(status="success", message=f"Download complete for {movie_url}"), 200
    except requests.exceptions.RequestException as e:
        return jsonify(status="error", message="Download failed.", details=str(e)), 500
    except Exception as e:
        return jsonify(status="error", message="An unexpected error occurred.", details=str(e)), 500


@movie_api_blueprint.route('/start', methods=['POST'])
@require_token
def start_stream():
    """
    Configures a mediamtx path with a runOnDemand command to start ffmpeg.
    """
    movie_path_in_mediamtx = "/movies/current_movie.mp4"
    path_name = "stream"

    # This is the ffmpeg command that mediamtx will run on demand.
    # It reads from the movie path and publishes to its own RTSP server.
    ffmpeg_command = (
        "ffmpeg -re -i " + movie_path_in_mediamtx +
        " -c:v copy -c:a copy " +
        "-f rtsp -rtsp_transport tcp rtsp://localhost:8554/" + path_name
    )

    # This is the JSON payload for the mediamtx API
    config_payload = {
        "runOnDemand": ffmpeg_command
    }

    try:
        # The webhook now talks to the mediamtx API on the internal docker network
        mediamtx_api_url = f"http://mediamtx:9997/v3/config/paths/add/{path_name}"
        
        print(f"Sending configuration to mediamtx API: {mediamtx_api_url}")
        response = requests.post(mediamtx_api_url, json=config_payload, auth=('admin','admin'))
        response.raise_for_status() # Raise an exception for bad status codes

        return jsonify(
            status="success",
            message=f"Stream '{path_name}' is configured. It will start when the first viewer connects."
        ), 200

    except requests.exceptions.RequestException as e:
        return jsonify(status="error", message="Failed to configure mediamtx.", details=str(e)), 500