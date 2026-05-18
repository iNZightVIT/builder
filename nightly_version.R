# Backward-compatible wrapper for development installer version.
source("scripts/channel_version.R")
cat(channel_version("development"))
