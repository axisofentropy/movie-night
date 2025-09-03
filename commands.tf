resource "discord-interactions_global_command" "start" {
  name        = "start"
  description = "Start streaming a movie from a URL."

  option {
    type        = 3 # STRING
    name        = "path_name"
    description = "The URL path for the stream (e.g., 'movie')"
    required    = true
  }

  option {
    type        = 3 # STRING
    name        = "url"
    description = "The URL of the movie file to stream"
    required    = true
  }
}
