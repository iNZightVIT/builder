# Shared channel helpers (sourced by scripts/install_channel.R, build_binaries.R, etc.)

DEFAULT_BINARY_REPO <- "https://r.docker.stat.auckland.ac.nz"
DEFAULT_CRAN <- "https://cran.rstudio.com"

read_channel_deps <- function(channel) {
  path <- file.path("channels", paste0(channel, ".deps"))
  if (!file.exists(path)) {
    stop("Channel deps file not found: ", path, call. = FALSE)
  }
  if (!requireNamespace("yaml", quietly = TRUE)) {
    install.packages("yaml", repos = DEFAULT_CRAN)
  }
  deps <- yaml::read_yaml(path)
  if (is.null(deps$packages) || !length(deps$packages)) {
    stop("No packages listed in ", path, call. = FALSE)
  }
  deps$channel <- channel
  if (is.null(deps$r_version)) {
    deps$r_version <- "4.1"
  }
  if (is.null(deps$rtools)) {
    deps$rtools <- "40"
  }
  if (is.null(deps$channel_type)) {
    deps$channel_type <- if (isTRUE(deps$overrides_only)) "pinned" else "stable"
  }
  if (is.null(deps$overrides_only)) {
    deps$overrides_only <- FALSE
  }
  deps
}

list_channels <- function() {
  files <- list.files("channels", pattern = "\\.deps$", full.names = FALSE)
  sub("\\.deps$", "", files[!grepl("^_", files)])
}

r_minor_version <- function() {
  paste(strsplit(as.character(getRversion()), "\\.")[[1]][1:2], collapse = ".")
}

channel_contrib_rel <- function(channel, r_minor = r_minor_version()) {
  file.path(channel, "bin", "windows", "contrib", r_minor)
}

channel_contrib_dir <- function(channel, r_minor = r_minor_version()) {
  file.path("staging", channel_contrib_rel(channel, r_minor))
}

channel_binary_repo_url <- function(channel) {
  base <- Sys.getenv("INZIGHT_REPO_BASE", unset = DEFAULT_BINARY_REPO)
  sub("/$", "", base)
}

channel_install_repos <- function(channel) {
  base <- channel_binary_repo_url(channel)
  c(
    file.path(base, channel),
    base,
    DEFAULT_CRAN
  )
}

hash_channel_inputs <- function(channel) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    install.packages("digest", repos = DEFAULT_CRAN)
  }
  files <- c(
    file.path("channels", paste0(channel, ".deps")),
    "channels/_shared.R",
    "R/channel_resolve.R",
    "scripts/install_channel.R",
    "scripts/build_binaries.R",
    "scripts/build_rgtk2_channel.R",
    "scripts/build_rgtk2_windows_artifacts.R",
    "scripts/install_channel_from_repo.R",
    "install_gtk.R",
    "R/rgtk2_cairo_install.R",
    "scripts/promote_repos.py"
  )
  missing <- files[!file.exists(files)]
  if (length(missing)) {
    stop("Missing hash input file(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }
  lines <- vapply(files, function(f) {
    paste(c(f, readLines(f, warn = FALSE)), collapse = "\n")
  }, character(1))
  digest::digest(paste(lines, collapse = "\n"), algo = "sha256")
}

parse_cli_channel <- function(args = commandArgs(TRUE)) {
  channel <- NA_character_
  for (a in args) {
    if (grepl("^--channel=", a)) {
      channel <- sub("^--channel=", "", a)
    }
  }
  if (!nzchar(channel)) {
    stop("Usage: Rscript script.R --channel=<name>", call. = FALSE)
  }
  channel
}

write_channel_lock <- function(channel) {
  ip <- installed.packages()
  ip <- ip[ip[, "Package"] %in% rownames(ip), , drop = FALSE]
  lock_path <- file.path("channels", paste0(channel, ".lock"))
  utils::write.csv(
    ip[, c("Package", "Version", "Priority", "Depends", "Imports", "LinkingTo")],
    lock_path,
    row.names = FALSE
  )
  invisible(lock_path)
}
