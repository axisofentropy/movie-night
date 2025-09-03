import os
import requests

# Get the secret Bot Token from an environment variable
BOT_TOKEN = os.environ.get("DISCORD_BOT_TOKEN")
APP_ID = os.environ.get("DISCORD_APP_ID")

if not BOT_TOKEN:
    raise ValueError("DISCORD_BOT_TOKEN environment variable not set.")
if not APP_ID:
    raise ValueError("DISCORD_APP_ID environment variable not set.")

url = f"https://discord.com/api/v10/applications/{APP_ID}/commands"

headers = {
    "Authorization": f"Bot {BOT_TOKEN}"
}

commands = [
    {
        "name": "start",
        "description": "Start streaming a movie from a URL.",
        "options": [
            {"type": 3, "name": "path_name", "description": "The URL path for the stream (e.g., 'movie')", "required": True},
            {"type": 3, "name": "url", "description": "The URL of the movie file to stream", "required": True}
        ]
    }
]

print("Registering commands with Discord...")
for command in commands:
    r = requests.post(url, headers=headers, json=command)
    r.raise_for_status()
    print(f"Registered command: {command['name']}")

print("All commands registered successfully.")