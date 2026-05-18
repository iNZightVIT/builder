# Installer version string for a channel (printed to stdout).
channel_version <- function(channel) {
  source("channels/_shared.R", local = TRUE)
  deps <- read_channel_deps(channel)

  if (!requireNamespace("iNZight", quietly = TRUE)) {
    stop("iNZight must be installed before computing channel version", call. = FALSE)
  }

  v <- strsplit(as.character(packageVersion("iNZight")), "\\.")[[1]]

  if (deps$channel_type == "development") {
    if (length(v) < 3L) {
      v <- c(v, rep("0", 3L - length(v)))
    } else if (length(v) == 3L) {
      v[4] <- format(Sys.time(), "%Y%m%d", tz = "Pacific/Auckland")
    } else if (length(v) == 4L) {
      v[4] <- ifelse(
        v[4] == "9000",
        format(Sys.time(), "%Y%m%d", tz = "Pacific/Auckland"),
        v[4]
      )
    } else {
      stop("Invalid iNZight version number")
    }
  } else if (length(v) < 3L) {
    v <- c(v, rep("0", 3L - length(v)))
  }

  paste(v, collapse = ".")
}

if (sys.nframe() == 0L) {
  source("channels/_shared.R", local = TRUE)
  cat(channel_version(parse_cli_channel(commandArgs(TRUE))))
}
