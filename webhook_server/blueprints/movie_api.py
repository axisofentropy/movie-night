import os
import subprocess
from functools import wraps
from flask import Blueprint, request, current_app, abort, jsonify
import requests
import docker # Import the docker library

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
    try:
        with requests.get(movie_url, stream=True) as r:
            r.raise_for_status()
            with open(output_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192): 
                    f.write(chunk)
        return jsonify(status="success", message=f"Download complete for {movie_url}"), 200
    except requests.exceptions.RequestException as e:
        return jsonify(status="error", message="Download failed.", details=str(e)), 500
    except Exception as e:
        return jsonify(status="error", message="An unexpected error occurred.", details=str(e)), 500


@movie_api_blueprint.route('/start', methods=['POST'])
@require_token
def start_stream():
    """
    Webhook to start the ffmpeg container directly using the Docker Python SDK.
    """
    movie_path_internal = "/downloads/current_movie.mp4"
    
    # This path comes from the startup script env var
    movies_dir_host = os.environ.get("MOVIES_DIR", "/home/chronos/movies") 

    # Check if the movie file exists inside the container
    if not os.path.exists(movie_path_internal):
        return jsonify(status="error", message=f"Movie file not found at {movie_path_internal}. Please download it first."), 404

    try:
        # The client will automatically use the DOCKER_HOST env var to connect to the proxy
        client = docker.from_env()

        # Define the ffmpeg command as a list of strings
        ffmpeg_command = [
            "-re", "-i", movie_path_internal,
            "-c:v", "copy", "-c:a", "copy",
            "-f", "rtsp", "-rtsp_transport", "tcp", "rtsp://mediamtx:8554/stream"
        ]

        print("Starting ffmpeg container...")
        # Run the container, translating docker run flags to Python arguments
        container = client.containers.run(
            image="linuxserver/ffmpeg",
            command=ffmpeg_command,
            name="ffmpeg-streamer",
            network="movie-night-net",
            volumes={movies_dir_host: {'bind': '/downloads', 'mode': 'ro'}},
            auto_remove=True,
            detach=True  # Run in the background
        )
        print(f"Started ffmpeg container with ID: {container.id}")
        return jsonify(status="success", message="Stream container started.", container_id=container.id), 200

    except docker.errors.APIError as e:
        return jsonify(status="error", message="Docker API Error.", details=str(e)), 500
    except Exception as e:
        return jsonify(status="error", message="An unexpected error occurred.", details=str(e)), 500