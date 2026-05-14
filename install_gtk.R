# GTK + RGtk2 + cairoDevice for Windows CI and local builds.
# Default (Windows): install.packages(type = "win.binary") from the iNZight package
# repository (override with INZIGHT_BINARY_REPO, default https://r.docker.stat.auckland.ac.nz),
# then unpack the GTK+ bundle beside RGtk2.
# Override with INZIGHT_RGTK2_ZIPS_DIR or INZIGHT_RGTK2_ZIP_URL + INZIGHT_CAIRODEVICE_ZIP_URL
# for local zip installs. No source compile of RGtk2/cairoDevice on CI when compile is disabled.
# Operator builds on Windows: scripts/build_rgtk2_windows_artifacts.R (optional .env + S3 upload).

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

## Returns list(RGtk2 = path, cairoDevice = path) for zip-based install, or NULL to use repo.
resolve_windows_binary_zip_paths <- function() {
  zdir <- Sys.getenv("INZIGHT_RGTK2_ZIPS_DIR", unset = "")
  if (nzchar(zdir) && dir.exists(zdir)) {
    z <- list.files(zdir, pattern = "\\.zip$", full.names = TRUE, ignore.case = TRUE)
    rgtk <- z[grepl("^RGtk2_.*\\.zip$", basename(z), ignore.case = TRUE)]
    cairo <- z[grepl("^cairoDevice_.*\\.zip$", basename(z), ignore.case = TRUE)]
    if (length(rgtk) == 1L && length(cairo) == 1L) {
      return(list(RGtk2 = rgtk[[1]], cairoDevice = cairo[[1]]))
    }
    if (length(rgtk) > 1L || length(cairo) > 1L) {
      stop("INZIGHT_RGTK2_ZIPS_DIR must contain exactly one RGtk2_*.zip and one cairoDevice_*.zip")
    }
  }
  e1 <- Sys.getenv("INZIGHT_RGTK2_ZIP_URL", unset = "")
  e2 <- Sys.getenv("INZIGHT_CAIRODEVICE_ZIP_URL", unset = "")
  if (nzchar(e1) && nzchar(e2)) {
    return(list(RGtk2 = e1, cairoDevice = e2))
  }
  NULL
}

install_rgtk_cairo_from_repo <- function(lib) {
  repo <- Sys.getenv("INZIGHT_BINARY_REPO", unset = "https://r.docker.stat.auckland.ac.nz")
  o <- options(install.packages.compile.from.source = "never")
  on.exit(options(o), add = TRUE)
  ap <- tryCatch(
    available.packages(repos = repo, type = "win.binary"),
    error = function(e) {
      matrix(nrow = 0L, ncol = 0L)
    }
  )
  need <- c("RGtk2", "cairoDevice")
  miss <- need[!need %in% rownames(ap)]
  if (length(miss)) {
    stop(
      "No win.binary ",
      paste(miss, collapse = ", "),
      " for R ",
      r_minor,
      " on ",
      repo,
      ".\nPublish binaries under bin/windows/contrib/",
      r_minor,
      "/ on that repository, or set INZIGHT_RGTK2_ZIPS_DIR / *_ZIP_URL for local zips.\n",
      "Build zips on a physical Windows machine: Rscript scripts/build_rgtk2_windows_artifacts.R\n"
    )
  }
  message("Installing RGtk2 and cairoDevice (win.binary) from ", repo)
  install.packages(need, lib = lib, repos = repo, type = "win.binary")
}

## Move unpacked GTK tree into <rgtk2_root>/gtk/x64/ (Windows: file.rename() fails across
## drive letters, e.g. %TEMP% on C: vs R library on D: on GHA — use copy then unlink.)
layout_unpacked_gtk_for_rgtk2 <- function(from, rgtk2_root) {
  gtk_dest <- file.path(rgtk2_root, "gtk", "x64")
  dir.create(file.path(rgtk2_root, "gtk"), recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(gtk_dest)) unlink(gtk_dest, recursive = TRUE)
  dir.create(gtk_dest, recursive = TRUE, showWarnings = FALSE)
  items <- list.files(from, full.names = TRUE, all.files = TRUE)
  items <- items[!basename(items) %in% c(".", "..")]
  if (!length(items)) stop("empty GTK unpack at ", from)
  ok <- file.copy(items, gtk_dest, recursive = TRUE, copy.date = TRUE)
  if (length(ok) != length(items) || !all(ok)) {
    stop("could not copy GTK bundle into ", gtk_dest)
  }
  unlink(from, recursive = TRUE)
  invisible(gtk_dest)
}

if (.Platform$OS.type == "windows") {
  lib <- .libPaths()[1]
  urls <- resolve_windows_binary_zip_paths()

  zr <- zc <- NA_character_
  if (!is.null(urls)) {
    td <- tempfile("rgtk2-zip-")
    dir.create(td)
    on.exit(unlink(td, recursive = TRUE), add = TRUE)

    zip_name <- function(u) {
      if (grepl("^https?://", u)) basename(u) else basename(normalizePath(u, winslash = "/"))
    }
    zr <- file.path(td, zip_name(urls$RGtk2))
    zc <- file.path(td, zip_name(urls$cairoDevice))
    download_if_url(urls$RGtk2, zr)
    download_if_url(urls$cairoDevice, zc)

    o <- options(install.packages.compile.from.source = "never")
    on.exit(options(o), add = TRUE)
    message("Installing RGtk2 (win.binary) into ", lib)
    install.packages(zr, lib = lib, repos = NULL, type = "win.binary")
    message("Installing cairoDevice (win.binary) into ", lib)
    install.packages(zc, lib = lib, repos = NULL, type = "win.binary")
  } else {
    install_rgtk_cairo_from_repo(lib)
  }


  cat("Downloading gtk ...\n")
  gtk_url <- Sys.getenv(
    "INZIGHT_GTK_BUNDLE_URL",
    unset = "http://ftp.gnome.org/pub/gnome/binaries/win64/gtk+/2.22/gtk+-bundle_2.22.1-20101229_win64.zip"
  )
  td_gtk <- tempfile("gtk-zip-")
  dir.create(td_gtk)
  on.exit(unlink(td_gtk, recursive = TRUE), add = TRUE)
  gtk_zip <- file.path(td_gtk, "gtk.zip")
  download.file(gtk_url, destfile = gtk_zip, mode = "wb")
  gtk_stage <- file.path(td_gtk, "gtk-unpack")
  dir.create(gtk_stage)
  unzip(gtk_zip, exdir = gtk_stage)
  file.remove(gtk_zip)

  rgtk2_root <- file.path(lib, "RGtk2")
  subs <- dir(gtk_stage, full.names = TRUE)
  subs <- subs[!is.na(file.info(subs)$isdir) & file.info(subs)$isdir]
  from <- if (length(subs) == 1L) subs else gtk_stage
  gtk_dest <- layout_unpacked_gtk_for_rgtk2(from, rgtk2_root)

  Sys.setenv(GTK_PATH = gtk_dest)

  contrib <- file.path("bin", "windows", "contrib", r_minor)
  if (!is.null(urls) && dir.exists(contrib) && !is.na(zr) && file.exists(zr)) {
    message("Copying RGtk2/cairoDevice zips into ", contrib)
    file.copy(c(zr, zc), contrib, overwrite = TRUE)
    tools::write_PACKAGES(contrib, type = "win.binary", verbose = TRUE)
  }

  invisible(list(zip_sources = urls, contrib = contrib, from_repo = is.null(urls)))
} else {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    cat("Installing remotes ...\n")
    install.packages("remotes")
  }
  if (!requireNamespace("RGtk2", quietly = TRUE)) {
    cat("Installing RGtk2 ...\n")
    remotes::install_github(
      "tmelliott/RGtk2/RGtk2",
      type = "source",
      build = FALSE,
      INSTALL_opts = c("--no-test-load")
    )
  }
  if (!requireNamespace("cairoDevice", quietly = TRUE)) {
    cat("Installing cairoDevice ...\n")
    install.packages(
      "cairoDevice",
      type = "source",
      build = FALSE
    )
  }
}
