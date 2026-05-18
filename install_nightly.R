# Backward-compatible wrapper for the development channel.
message("install_nightly.R: delegating to scripts/install_channel.R --channel=development")
source("scripts/install_channel.R")
install_channel("development")
