# Install packages for a build channel from channels/<channel>.deps
install_channel <- function(channel) {
  source("channels/_shared.R", local = TRUE)
  source("R/channel_resolve.R", local = TRUE)

  deps <- read_channel_deps(channel)

  r_target <- deps$r_version
  r_cur <- paste(strsplit(as.character(getRversion()), "\\.")[[1]][1:2], collapse = ".")
  if (r_cur != r_target) {
    warning(
      "R version is ", r_cur, " but channel expects ", r_target,
      call. = FALSE
    )
  }

  options(
    repos = channel_install_repos(channel),
    install.packages.compile.from.source = "never",
    pkg.windows_archs = "prefer-x64",
    pkg.build = FALSE
  )

  if (!requireNamespace("pak", quietly = TRUE)) {
    install.packages("pak",
      repos = DEFAULT_CRAN, type = "source",
      INSTALL_opts = c("--no-multiarch", "--no-test-load", "--no-docs")
    )
  }

  if (deps$channel_type == "development") {
    pak::pak(c("httr", "lubridate"))
  }

  resolved <- resolve_channel_packages(deps)
  message("Installing ", length(resolved), " package(s) for channel '", channel, "':")
  print(resolved)

  pak::pkg_install(resolved)

  write_channel_lock(channel)
  message("Wrote lock file: channels/", channel, ".lock")
  invisible(resolved)
}

if (sys.nframe() == 0L) {
  source("channels/_shared.R", local = TRUE)
  install_channel(parse_cli_channel(commandArgs(TRUE)))
}
