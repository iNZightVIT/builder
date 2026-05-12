# GTK + RGtk2 + cairoDevice for Windows CI and local builds.
# Curated win.binary zips only — no compilation of these packages on GHA.
# Operator builds on Windows: scripts/build_rgtk2_windows_artifacts.R (optional .env + S3 upload).

r_minor <- paste(
  strsplit(as.character(getRversion()), "\\.")[[1]][1:2],
  collapse = "."
)

## Tier 1: published mirror URLs per R minor (versions must exist on the mirror).
mirror_binary_urls <- list(
  "4.0" = list(
    RGtk2 = "https://r.docker.stat.auckland.ac.nz/bin/windows/contrib/4.0/RGtk2_2.20.36.3.zip",
    cairoDevice = "https://r.docker.stat.auckland.ac.nz/bin/windows/contrib/4.0/cairoDevice_2.28.2.2.zip"
  ),
  "4.1" = list(
    RGtk2 = "https://r.docker.stat.auckland.ac.nz/bin/windows/contrib/4.1/RGtk2_2.20.36.3.zip",
    cairoDevice = "https://r.docker.stat.auckland.ac.nz/bin/windows/contrib/4.1/cairoDevice_2.28.2.2.zip"
  )
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

resolve_windows_binary_zips <- function() {
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
  if (r_minor %in% names(mirror_binary_urls)) {
    return(mirror_binary_urls[[r_minor]])
  }
  stop(
    "No pre-built RGtk2/cairoDevice zips for R ", r_minor, ".\n",
    "Options:\n",
    "  - Sync zips into a directory and set INZIGHT_RGTK2_ZIPS_DIR, or\n",
    "  - Set INZIGHT_RGTK2_ZIP_URL and INZIGHT_CAIRODEVICE_ZIP_URL (URLs or local paths), or\n",
    "  - Publish zips under bin/windows/contrib/", r_minor, "/ on the mirror (tier 1 list in install_gtk.R).\n",
    "Build zips on a physical Windows machine: Rscript scripts/build_rgtk2_windows_artifacts.R\n"
  )
}

if (.Platform$OS.type == "windows") {
  urls <- resolve_windows_binary_zips()
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

  lib <- .libPaths()[1]
  message("Installing RGtk2 (win.binary) into ", lib)
  install.packages(zr, lib = lib, repos = NULL, type = "win.binary")
  message("Installing cairoDevice (win.binary) into ", lib)
  install.packages(zc, lib = lib, repos = NULL, type = "win.binary")

  cat("Downloading gtk ...\n")
  gtk_url <- Sys.getenv(
    "INZIGHT_GTK_BUNDLE_URL",
    unset = "https://inzight.nz/data/gtk+-bundle_2.22.1-20101229_win64.zip"
  )
  gtk_zip <- file.path(td, "gtk.zip")
  download.file(gtk_url, destfile = gtk_zip, mode = "wb")
  gtk_stage <- file.path(td, "gtk-unpack")
  dir.create(gtk_stage)
  unzip(gtk_zip, exdir = gtk_stage)
  file.remove(gtk_zip)

  rgtk2_root <- file.path(lib, "RGtk2")
  gtk_dest <- file.path(rgtk2_root, "gtk", "x64")
  if (dir.exists(gtk_dest)) unlink(gtk_dest, recursive = TRUE)
  dir.create(file.path(rgtk2_root, "gtk"), recursive = TRUE)
  subs <- dir(gtk_stage, full.names = TRUE)
  subs <- subs[!is.na(file.info(subs)$isdir) & file.info(subs)$isdir]
  from <- if (length(subs) == 1L) subs else gtk_stage
  file.rename(from, gtk_dest)

  Sys.setenv(GTK_PATH = gtk_dest)

  contrib <- file.path("bin", "windows", "contrib", r_minor)
  if (dir.exists(contrib)) {
    message("Copying RGtk2/cairoDevice zips into ", contrib)
    file.copy(c(zr, zc), contrib, overwrite = TRUE)
    tools::write_PACKAGES(contrib, type = "win.binary", verbose = TRUE)
  }

  invisible(list(RGtk2 = zr, cairoDevice = zc, contrib = contrib))
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
