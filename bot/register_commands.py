import os
import requests

# Your bot's public Application ID
APP_ID = "1401758890244444241"

# Get the secret Bot Token from an environment variable
BOT_TOKEN = os.environ.get("DISCORD_BOT_TOKEN")

if not BOT_TOKEN:
    raise ValueError("DISCORD_BOT_TOKEN environment variable not set.")

url = f"https://discord.com/api/v10/applications/{APP_ID}/commands"

headers = {
    "Authorization": f"Bot {BOT_TOKEN}"
}

commands = [
    {
        "name": "download",
        "description": "Download a movie to the server.",
        "options": [
            {"type": 3, "name": "url", "description": "The URL of the movie file", "required": True},
            {"type": 3, "name": "filename", "description": "The name to save the file as (e.g., movie.mp4)", "required": True}
        ]
    },
    {
        "name": "start",
        "description": "Start the movie stream.",
        "options": [
            {"type": 3, "name": "path_name", "description": "The URL path for the stream (e.g., 'movie')", "required": True},
            {"type": 3, "name": "filename", "description": "The filename of the downloaded movie to stream", "required": True}
        ]
    }
]

print("Registering commands with Discord...")
for command in commands:
    r = requests.post(url, headers=headers, json=command)
    r.raise_for_status()
    print(f"Registered command: {command['name']}")

print("All commands registered successfully.")