import subprocess
from functools import wraps
from flask import Blueprint, request, current_app, abort, jsonify
import requests # Import the requests library

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


@movie_api_blueprint.route('/download', methods=['POST'])
@require_token
def download_movie():
    """
    Webhook to download a movie directly using Python.
    Expects the raw request body to be the URL.
    """
    movie_url = request.data.decode('utf-8')
    if not movie_url:
        abort(400, description="Bad Request: The request body cannot be empty.")

    output_path = "/downloads/current_movie.mp4"
    
    try:
        print(f"Starting download from {movie_url}...")
        # Use a streaming request to handle large files efficiently
        with requests.get(movie_url, stream=True) as r:
            r.raise_for_status() # Will raise an exception for bad status codes (4xx or 5xx)
            with open(output_path, 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192): 
                    f.write(chunk)
        
        print(f"Download finished. File saved to {output_path}")
        return jsonify(status="success", message=f"Download complete for {movie_url}"), 200

    except requests.exceptions.RequestException as e:
        return jsonify(status="error", message="Download failed.", details=str(e)), 500
    except Exception as e:
        return jsonify(status="error", message="An unexpected error occurred.", details=str(e)), 500

# ... (start_stream function remains the same, using subprocess) ...
@movie_api_blueprint.route('/start', methods=['POST'])
@require_token
def start_stream():
    """
    Webhook to start the ffmpeg container via the Docker proxy.
    """
    try:
        # Execute the stream start script
        result = subprocess.run(
            ["/scripts/start_stream.sh"],
            check=True, text=True, capture_output=True
        )
        return jsonify(status="success", message="Stream start command issued.", output=result.stdout), 200
    except subprocess.CalledProcessError as e:
        return jsonify(status="error", message="Start stream script failed.", details=e.stderr), 500