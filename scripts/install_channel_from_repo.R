# Install channel packages from promoted S3 repos (win.binary only).
# Used by the installer CI job after promote-repos; does not use pak::pkg_install.
install_channel_from_repo <- function(channel) {
  source("channels/_shared.R", local = TRUE)
  source("R/channel_resolve.R", local = TRUE)

  deps <- read_channel_deps(channel)
  repos <- channel_install_repos(channel)

  options(
    repos = repos,
    install.packages.compile.from.source = "never",
    pkg.windows_archs = "prefer-x64"
  )

  if (deps$channel_type == "development") {
    pre <- c("httr", "lubridate")
    ap <- available.packages(repos = repos, type = "win.binary")
    miss <- pre[!pre %in% rownames(ap)]
    if (length(miss)) {
      stop(
        "No win.binary ",
        paste(miss, collapse = ", "),
        " on channel repos (needed to resolve development packages).",
        call. = FALSE
      )
    }
    install.packages(pre, lib = .libPaths()[1], repos = repos, type = "win.binary")
  }

  resolved <- resolve_channel_packages(deps)
  pkg_names <- unique(vapply(resolved, pkg_name_from_spec, character(1)))
  pkg_names <- setdiff(pkg_names, c("RGtk2", "cairoDevice"))

  ap <- available.packages(repos = repos, type = "win.binary")
  missing <- pkg_names[!pkg_names %in% rownames(ap)]
  if (length(missing)) {
    stop(
      "No win.binary on promoted repos for: ",
      paste(missing, collapse = ", "),
      "\nRepos: ",
      paste(repos, collapse = ", "),
      "\nEnsure build-channel-repo completed and promote-repos ran.",
      call. = FALSE
    )
  }

  message(
    "Installing ",
    length(pkg_names),
    " package(s) for channel '",
    channel,
    "' from promoted repos:"
  )
  print(pkg_names)
  install.packages(
    pkg_names,
    lib = .libPaths()[1],
    repos = repos,
    type = "win.binary"
  )
  invisible(pkg_names)
}

if (sys.nframe() == 0L) {
  source("channels/_shared.R", local = TRUE)
  channel <- parse_cli_channel(commandArgs(TRUE))
  Sys.setenv(INZIGHT_CHANNEL = channel)
  install_channel_from_repo(channel)
}
