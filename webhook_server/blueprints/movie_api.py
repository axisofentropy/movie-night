import subprocess
from functools import wraps
from flask import Blueprint, request, current_app, abort, jsonify

# Create a Blueprint object
movie_api_blueprint = Blueprint('movie_api', __name__)

# --- Security Decorator ---
# This checks the token for any route it's applied to.
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
    Expects the raw request body to be the URL.
    """
    movie_url = request.data.decode('utf-8')
    if not movie_url:
        abort(400, description="Bad Request: The request body cannot be empty.")
    
    try:
        # Execute the download script, passing the URL as an argument
        subprocess.run(
            ["/scripts/download_movie.sh", movie_url],
            check=True, text=True, capture_output=True
        )
        return jsonify(status="success", message=f"Download initiated for {movie_url}"), 200
    except subprocess.CalledProcessError as e:
        return jsonify(status="error", message="Download script failed.", details=e.stderr), 500

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