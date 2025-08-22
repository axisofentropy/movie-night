#!/bin/bash
set -e

MOVIE_PATH="/downloads/current_movie.mp4"
NETWORK_NAME="movie-night-net"

# Check if the movie file exists before trying to stream it
if [ ! -f "$MOVIE_PATH" ]; then
    echo "Error: Movie file not found at ${MOVIE_PATH}. Please download it first."
    exit 1
fi

echo "Found movie file. Starting ffmpeg container via proxy..."

# The DOCKER_HOST env var will route this command to the proxy.
# The proxy's rules will only allow it if the image is 'linuxserver/ffmpeg'.
docker run \
  --rm \
  --network="${NETWORK_NAME}" \
  -v "${MOVIES_DIR:-/opt/movies}:/downloads:ro" \
  --name ffmpeg-streamer \
  linuxserver/ffmpeg -hide_banner -loglevel error \
  -re -i /downloads/current_movie.mp4 \
  -c:v copy -c:a copy \
  -f rtsp -rtsp_transport tcp rtsp://mediamtx:8554/stream

# Note: The above is a simple ffmpeg command. You can replace it
# with the more complex transcoding one from your original script.
echo "ffmpeg container started."