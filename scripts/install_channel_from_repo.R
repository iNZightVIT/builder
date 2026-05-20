# Install channel packages from promoted S3 repos (win.binary only).
# Used by the installer CI job after promote-repos; does not use pak::pkg_install.
install_channel_from_repo <- function(channel) {
  source("channels/_shared.R", local = TRUE)
  source("R/channel_resolve.R", local = TRUE)

  deps <- read_channel_deps(channel)
  repos <- channel_install_repos(channel)
  lib <- Sys.getenv("R_LIBS_USER", unset = "")
  if (!nzchar(lib)) {
    lib <- .libPaths()[1]
  }
  lib <- normalizePath(lib, winslash = "/", mustWork = TRUE)

  options(
    repos = repos,
    install.packages.compile.from.source = "never",
    pkg.windows_archs = "prefer-x64"
  )

  message("Channel repos:\n", paste0("  ", repos, collapse = "\n"))
  message("R library: ", lib)

  assert_installed <- function(pkgs) {
    ip <- rownames(installed.packages(lib.loc = lib))
    miss <- pkgs[!pkgs %in% ip]
    if (length(miss)) {
      stop(
        "Package(s) missing after install: ",
        paste(miss, collapse = ", "),
        "\nLibrary: ",
        lib,
        call. = FALSE
      )
    }
  }

  install_win_binaries <- function(pkgs) {
    if (!length(pkgs)) {
      return(invisible(character(0)))
    }
    message("Installing: ", paste(pkgs, collapse = ", "))
    out <- tryCatch(
      install.packages(pkgs, lib = lib, repos = repos, type = "win.binary"),
      error = function(e) e
    )
    if (inherits(out, "error")) {
      stop("install.packages failed: ", conditionMessage(out), call. = FALSE)
    }
    assert_installed(pkgs)
    invisible(pkgs)
  }

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
    install_win_binaries(pre)
  }

  resolved <- resolve_channel_packages(deps)
  pkg_names <- unique(vapply(resolved, pkg_name_from_spec, character(1)))

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

  gtk_pkgs <- intersect(c("RGtk2", "cairoDevice"), pkg_names)
  other_pkgs <- setdiff(pkg_names, gtk_pkgs)

  message(
    "Installing ",
    length(pkg_names),
    " package(s) for channel '",
    channel,
    "' from promoted repos"
  )
  install_win_binaries(gtk_pkgs)
  install_win_binaries(other_pkgs)

  if (!"iNZight" %in% pkg_names) {
    warning("iNZight not listed in channel deps", call. = FALSE)
  } else {
    assert_installed("iNZight")
  }

  invisible(pkg_names)
}

if (sys.nframe() == 0L) {
  source("channels/_shared.R", local = TRUE)
  channel <- parse_cli_channel(commandArgs(TRUE))
  Sys.setenv(INZIGHT_CHANNEL = channel)
  install_channel_from_repo(channel)
}
