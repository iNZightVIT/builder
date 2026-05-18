# Shared RGtk2 / cairoDevice install helpers (Windows CI and curator builds).

DEFAULT_CRAN <- "https://cloud.r-project.org"

resolve_rgtk2_src <- function(root = getwd()) {
  explicit <- Sys.getenv("INZIGHT_RGTK2_SOURCE", unset = "")
  if (nzchar(explicit) && dir.exists(explicit)) {
    return(normalizePath(explicit, winslash = "/", mustWork = TRUE))
  }
  for (p in c(
    file.path(root, "src", "RGtk2", "RGtk2"),
    file.path(root, "library", "RGtk2"),
    file.path(root, "RGtk2", "RGtk2")
  )) {
    if (dir.exists(p)) {
      return(normalizePath(p, winslash = "/", mustWork = TRUE))
    }
  }
  NA_character_
}

resolve_cairo_src <- function(root = getwd()) {
  explicit <- Sys.getenv("INZIGHT_CAIRODEVICE_SOURCE", unset = "")
  if (nzchar(explicit) && dir.exists(explicit)) {
    return(normalizePath(explicit, winslash = "/", mustWork = TRUE))
  }
  p <- file.path(root, "library", "cairoDevice")
  if (dir.exists(p)) {
    return(normalizePath(p, winslash = "/", mustWork = TRUE))
  }
  NA_character_
}

resolve_rgtk_repos <- function() {
  channel <- Sys.getenv("INZIGHT_CHANNEL", unset = "")
  if (nzchar(channel) && file.exists("channels/_shared.R")) {
    local({
      source("channels/_shared.R", local = TRUE)
      return(channel_install_repos(channel))
    })
  }
  base <- Sys.getenv("INZIGHT_BINARY_REPO", unset = "https://r.docker.stat.auckland.ac.nz")
  c(sub("/$", "", base), DEFAULT_CRAN)
}

ensure_remotes <- function() {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes", repos = DEFAULT_CRAN)
  }
}

available_win_binary <- function(repos) {
  tryCatch(
    available.packages(repos = repos, type = "win.binary"),
    error = function(e) {
      matrix(nrow = 0L, ncol = 0L)
    }
  )
}

install_win_binary_if_available <- function(pkg, lib, repos) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    return(invisible(TRUE))
  }
  ap <- available_win_binary(repos)
  if (!pkg %in% rownames(ap)) {
    return(invisible(FALSE))
  }
  o <- options(install.packages.compile.from.source = "never")
  on.exit(options(o), add = TRUE)
  message("Installing ", pkg, " (win.binary) from ", paste(repos, collapse = ", "))
  install.packages(pkg, lib = lib, repos = repos, type = "win.binary")
  invisible(TRUE)
}

install_rgtk2_from_source <- function(lib, root = getwd()) {
  if (requireNamespace("RGtk2", quietly = TRUE)) {
    return(invisible(TRUE))
  }
  ensure_remotes()
  rgtk2_src <- resolve_rgtk2_src(root)
  if (!is.na(rgtk2_src)) {
    message("Installing RGtk2 from source: ", rgtk2_src)
    remotes::install_local(
      rgtk2_src,
      lib = lib,
      dependencies = NA,
      upgrade = "never",
      INSTALL_opts = c("--no-multiarch", "--no-test-load")
    )
    return(invisible(TRUE))
  }
  ref <- Sys.getenv("INZIGHT_RGTK2_GITHUB", unset = "tmelliott/RGtk2/RGtk2")
  message("Installing RGtk2 from GitHub: ", ref)
  remotes::install_github(
    ref,
    lib = lib,
    upgrade = "never",
    INSTALL_opts = c("--no-multiarch", "--no-test-load")
  )
  invisible(TRUE)
}

install_cairodevice_from_source <- function(lib, root = getwd()) {
  if (requireNamespace("cairoDevice", quietly = TRUE)) {
    return(invisible(TRUE))
  }
  ensure_remotes()
  cairo_src <- resolve_cairo_src(root)
  if (!is.na(cairo_src)) {
    message("Installing cairoDevice from source: ", cairo_src)
    remotes::install_local(
      cairo_src,
      lib = lib,
      dependencies = NA,
      upgrade = "never",
      INSTALL_opts = c("--no-multiarch", "--no-test-load")
    )
    return(invisible(TRUE))
  }
  ref <- Sys.getenv("INZIGHT_CAIRODEVICE_GITHUB", unset = "tmelliott/cairoDevice")
  if (nzchar(ref)) {
    message("Installing cairoDevice from GitHub: ", ref)
    remotes::install_github(
      ref,
      lib = lib,
      upgrade = "never",
      INSTALL_opts = c("--no-multiarch", "--no-test-load")
    )
    return(invisible(TRUE))
  }
  cran <- DEFAULT_CRAN
  ap <- available_win_binary(cran)
  if ("cairoDevice" %in% rownames(ap)) {
    message("Installing cairoDevice (win.binary) from CRAN")
    o <- options(install.packages.compile.from.source = "never")
    on.exit(options(o), add = TRUE)
    install.packages("cairoDevice", lib = lib, repos = cran, type = "win.binary")
    return(invisible(TRUE))
  }
  message("Installing cairoDevice (source) from CRAN")
  install.packages(
    "cairoDevice",
    lib = lib,
    repos = cran,
    type = "source"
  )
  invisible(TRUE)
}

install_rgtk2_with_fallback <- function(lib, repos = resolve_rgtk_repos(), root = getwd()) {
  if (install_win_binary_if_available("RGtk2", lib, repos)) {
    return(invisible("win.binary"))
  }
  install_rgtk2_from_source(lib, root)
  invisible("source")
}

install_cairodevice_with_fallback <- function(lib, repos = resolve_rgtk_repos(), root = getwd()) {
  if (install_win_binary_if_available("cairoDevice", lib, repos)) {
    return(invisible("win.binary"))
  }
  install_cairodevice_from_source(lib, root)
  invisible("source")
}

install_rgtk_cairo_with_fallback <- function(lib, repos = resolve_rgtk_repos(), root = getwd()) {
  rgtk_method <- install_rgtk2_with_fallback(lib, repos, root)
  cairo_method <- install_cairodevice_with_fallback(lib, repos, root)
  invisible(list(RGtk2 = rgtk_method, cairoDevice = cairo_method))
}
