#!/bin/bash
set -e # Exit immediately if a command fails

# The first argument passed is the movie URL
MOVIE_URL="$1"
OUTPUT_PATH="/downloads/current_movie.mp4"

# Basic validation
if [ -z "$MOVIE_URL" ]; then
  echo "Error: No movie URL provided."
  exit 1
fi

echo "Downloading from URL: ${MOVIE_URL}"
# -L follows redirects, -o saves to a file (overwriting if it exists)
curl -L -s -o "${OUTPUT_PATH}" "${MOVIE_URL}"
echo "Download complete."