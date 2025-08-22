import os
from flask import Flask, jsonify
from blueprints.movie_api import movie_api_blueprint

# Initialize the Flask application
app = Flask(__name__)

# Load the secret token from an environment variable for security
# This will be provided in the 'docker run' command
app.config['SECRET_TOKEN'] = os.environ.get("SECRET_TOKEN")
if not app.config['SECRET_TOKEN']:
    raise ValueError("SECRET_TOKEN environment variable not set.")

# Register the blueprint for movie-related commands
app.register_blueprint(movie_api_blueprint, url_prefix='/movie')

# A simple root endpoint to confirm the server is running
@app.route('/')
def index():
    return jsonify(status="ok", message="Webhook server is running.")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)