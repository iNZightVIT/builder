# GTK + RGtk2 + cairoDevice for Windows CI and local builds.
# Win.binary from channel/flat repos when available; otherwise source (submodule,
# GitHub, or CRAN for cairoDevice). GTK bundle is added when RGtk2 lacks gtk/.
# Override with INZIGHT_RGTK2_ZIPS_DIR or *_ZIP_URL for local zip installs.

source("R/rgtk2_cairo_install.R", local = TRUE)

r_minor <- paste(
  strsplit(as.character(getRversion()), "\\.")[[1]][1:2],
  collapse = "."
)

download_if_url <- function(src, dest) {
  if (grepl("^https?://", src)) {
    status <- download.file(src, destfile = dest, mode = "wb")
    if (status != 0) stop("download failed: ", src)
  } else {
    if (!file.copy(src, dest, overwrite = TRUE)) {
      stop("could not copy: ", src)
    }
  }
  dest
}

## Returns list(RGtk2 = path|NULL, cairoDevice = path|NULL) for zip installs, or NULL.
resolve_windows_binary_zip_paths <- function() {
  zdir <- Sys.getenv("INZIGHT_RGTK2_ZIPS_DIR", unset = "")
  rgtk <- cairo <- character(0)
  if (nzchar(zdir) && dir.exists(zdir)) {
    z <- list.files(zdir, pattern = "\\.zip$", full.names = TRUE, ignore.case = TRUE)
    rgtk <- z[grepl("^RGtk2_.*\\.zip$", basename(z), ignore.case = TRUE)]
    cairo <- z[grepl("^cairoDevice_.*\\.zip$", basename(z), ignore.case = TRUE)]
  }
  e1 <- Sys.getenv("INZIGHT_RGTK2_ZIP_URL", unset = "")
  e2 <- Sys.getenv("INZIGHT_CAIRODEVICE_ZIP_URL", unset = "")
  if (nzchar(e1)) rgtk <- c(rgtk, e1)
  if (nzchar(e2)) cairo <- c(cairo, e2)
  if (length(rgtk) > 1L || length(cairo) > 1L) {
    stop("Multiple RGtk2_*.zip or cairoDevice_*.zip found; keep one of each.")
  }
  if (!length(rgtk) && !length(cairo)) {
    return(NULL)
  }
  list(
    RGtk2 = if (length(rgtk)) rgtk[[1]] else NULL,
    cairoDevice = if (length(cairo)) cairo[[1]] else NULL
  )
}

install_from_zip <- function(zip_path, pkg, lib) {
  o <- options(install.packages.compile.from.source = "never")
  on.exit(options(o), add = TRUE)
  message("Installing ", pkg, " (win.binary) into ", lib)
  install.packages(zip_path, lib = lib, repos = NULL, type = "win.binary")
}

layout_gtk_if_missing <- function(lib) {
  cat("Layout GTK runtime for RGtk2 ...\n")
  layout_gtk_runtime_for_lib(lib)
}

if (.Platform$OS.type == "windows") {
  lib <- .libPaths()[1]
  root <- Sys.getenv("INZIGHT_BUILDER_ROOT", unset = getwd())
  repos <- resolve_rgtk_repos()
  urls <- NULL
  zr <- zc <- NA_character_
  already_built <- tolower(Sys.getenv("INZIGHT_RGTK2_ALREADY_BUILT", unset = "")) %in%
    c("1", "true", "yes")

  if (already_built &&
      requireNamespace("RGtk2", quietly = TRUE) &&
      requireNamespace("cairoDevice", quietly = TRUE)) {
    message("RGtk2/cairoDevice already installed; ensuring GTK layout")
    layout_gtk_if_missing(lib)
  } else {
    urls <- resolve_windows_binary_zip_paths()
    methods <- list(RGtk2 = NA_character_, cairoDevice = NA_character_)

    if (!is.null(urls)) {
      td <- tempfile("rgtk2-zip-")
      dir.create(td)
      on.exit(unlink(td, recursive = TRUE), add = TRUE)
      zip_name <- function(u) {
        if (grepl("^https?://", u)) basename(u) else basename(normalizePath(u, winslash = "/"))
      }
      if (!is.null(urls$RGtk2)) {
        zr <- file.path(td, zip_name(urls$RGtk2))
        download_if_url(urls$RGtk2, zr)
        install_from_zip(zr, "RGtk2", lib)
        methods$RGtk2 <- "zip"
      }
      if (!is.null(urls$cairoDevice)) {
        zc <- file.path(td, zip_name(urls$cairoDevice))
        download_if_url(urls$cairoDevice, zc)
        install_from_zip(zc, "cairoDevice", lib)
        methods$cairoDevice <- "zip"
      }
    }

    if (is.na(methods$RGtk2)) {
      methods$RGtk2 <- install_rgtk2_with_fallback(lib, repos, root)
    }
    if (is.na(methods$cairoDevice)) {
      methods$cairoDevice <- install_cairodevice_with_fallback(lib, repos, root)
    }

    if (!requireNamespace("RGtk2", quietly = TRUE) ||
        !requireNamespace("cairoDevice", quietly = TRUE)) {
      stop(
        "Failed to install RGtk2 and/or cairoDevice.\n",
        "Set INZIGHT_RGTK2_ZIPS_DIR / *_ZIP_URL, init submodules, or publish win.binaries.",
        call. = FALSE
      )
    }

    layout_gtk_if_missing(lib)
  }

  gtk_dest <- file.path(lib, "RGtk2", "gtk", "x64")
  if (dir.exists(gtk_dest)) {
    Sys.setenv(GTK_PATH = gtk_dest)
  }

  contrib <- file.path("bin", "windows", "contrib", r_minor)
  ci <- nzchar(Sys.getenv("INZIGHT_CI", unset = ""))
  if (
    !ci &&
      !is.null(urls) &&
      dir.exists(contrib) &&
      !is.na(zr) &&
      file.exists(zr)
  ) {
    zips <- zr
    if (!is.na(zc) && file.exists(zc)) {
      zips <- c(zr, zc)
    }
    message("Copying RGtk2/cairoDevice zips into ", contrib)
    file.copy(zips, contrib, overwrite = TRUE)
    tools::write_PACKAGES(contrib, type = "win.binary", verbose = TRUE)
  }

  invisible(list(zip_sources = urls, contrib = contrib, methods = methods))
} else {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    cat("Installing remotes ...\n")
    install.packages("remotes")
  }
  root <- getwd()
  if (!requireNamespace("RGtk2", quietly = TRUE)) {
    install_rgtk2_from_source(lib = .libPaths()[1], root = root)
  }
  if (!requireNamespace("cairoDevice", quietly = TRUE)) {
    install_cairodevice_from_source(lib = .libPaths()[1], root = root)
  }
}
