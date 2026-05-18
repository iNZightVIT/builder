#!/usr/bin/env Rscript
# Curator script: build win.binary-style zips for RGtk2 and cairoDevice on real
# Windows hardware (one R minor per R session). Not used in GitHub Actions.
#
# Optional S3 upload (tier-2 prefix used by install_gtk.R) via the R package aws.s3
# (https://github.com/cloudyr/aws.s3) — no AWS CLI required unless you set
# INZIGHT_RGTK2_S3_USE_CLI=1 (then `aws` must be on PATH for aws s3 cp).
#
#   1) Create a .env in the working directory (or set INZIGHT_BUILDER_ENV_FILE to its path).
#      Credentials are read the same way as aws.s3 / aws.signature, e.g.:
#        AWS_ACCESS_KEY_ID=...
#        AWS_SECRET_ACCESS_KEY=...
#        AWS_SESSION_TOKEN=...          # omit if using long-lived keys
#        AWS_DEFAULT_REGION=ap-southeast-2
#      readRenviron() does not override variables already set in the shell.
#   2) Set INZIGHT_RGTK2_UPLOAD_S3=1 in .env (or pass --upload-s3) to upload after the build.
#      Optional: INZIGHT_RGTK2_S3_BUCKET (default r.docker.stat.auckland.ac.nz).
#   Do not commit .env (see .gitignore).

if (.Platform$OS.type != "windows") {
  stop("This script must be run on Windows.")
}

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default) {
  m <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(m)) sub(paste0("^--", name, "="), "", m[[1]]) else default
}

load_builder_env_file <- function() {
  path <- Sys.getenv("INZIGHT_BUILDER_ENV_FILE", unset = "")
  if (!nzchar(path)) {
    path <- file.path(getwd(), ".env")
  }
  if (file.exists(path)) {
    readRenviron(path)
    message("Loaded environment from: ", normalizePath(path, winslash = "/", mustWork = TRUE))
  }
}
load_builder_env_file()

output_dir <- get_arg("output-dir", file.path(getwd(), "rgtk2-artifacts"))
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

lib <- get_arg("lib", file.path(tempdir(), "rgtk2-curator-lib"))
if (!dir.exists(lib)) dir.create(lib, recursive = TRUE)

repo_root <- get_arg("root", Sys.getenv("INZIGHT_BUILDER_ROOT", unset = getwd()))
rgtk2_src <- Sys.getenv("INZIGHT_RGTK2_SOURCE", unset = "")
cairo_src <- Sys.getenv("INZIGHT_CAIRODEVICE_SOURCE", unset = "")

resolve_rgtk2_src <- function(root) {
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

if (!nzchar(rgtk2_src)) {
  rgtk2_src <- resolve_rgtk2_src(repo_root)
}
if (!nzchar(cairo_src)) {
  p <- file.path(repo_root, "library", "cairoDevice")
  if (dir.exists(p)) cairo_src <- p
}
use_github_rgtk2 <-
  is.na(rgtk2_src) || !nzchar(rgtk2_src) || !dir.exists(rgtk2_src)
if (!nzchar(cairo_src) || !dir.exists(cairo_src)) {
  stop(
    "cairoDevice source not found. Set INZIGHT_CAIRODEVICE_SOURCE or init library/cairoDevice submodule."
  )
}

if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", repos = "https://cloud.r-project.org")
}

gtk_url <- Sys.getenv(
  "INZIGHT_GTK_BUNDLE_URL",
  unset = "http://ftp.gnome.org/pub/gnome/binaries/win64/gtk+/2.22/gtk+-bundle_2.22.1-20101229_win64.zip"
)

## Same semantics as layout_unpacked_gtk_for_rgtk2 in install_gtk.R (cross-drive safe on Windows).
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

zip_win_binary <- function(pkg, lib, out_dir) {
  desc <- read.dcf(file.path(lib, pkg, "DESCRIPTION"))
  ver <- desc[1, "Version"]
  zipname <- sprintf("%s_%s.zip", pkg, ver)
  ow <- getwd()
  on.exit(setwd(ow), add = TRUE)
  setwd(lib)
  zpath <- file.path(out_dir, zipname)
  if (file.exists(zpath)) file.remove(zpath)
  utils::zip(zpath, pkg)
  normalizePath(zpath, winslash = "/", mustWork = TRUE)
}

publish_contrib_dir <- function(files, r_minor, root = getwd()) {
  contrib <- file.path(root, "bin", "windows", "contrib", r_minor)
  dir.create(contrib, recursive = TRUE, showWarnings = FALSE)
  file.copy(files, contrib, overwrite = TRUE)
  tools::write_PACKAGES(contrib, type = "win.binary", verbose = TRUE)
  normalizePath(contrib, winslash = "/", mustWork = TRUE)
}

upload_with_cli <- function(local_path, s3_dest) {
  aws <- Sys.which("aws")
  if (!nzchar(aws)) {
    stop("AWS CLI (`aws`) not on PATH; set INZIGHT_RGTK2_S3_USE_CLI=1 only when aws is available.")
  }
  prof <- trimws(Sys.getenv("AWS_PROFILE", unset = ""))
  argv <- c("s3", "sync", local_path, s3_dest)
  if (nzchar(prof)) {
    argv <- c(argv, "--profile", prof)
  }
  message("aws ", paste(argv, collapse = " "))
  st <- system2(aws, argv)
  if (!identical(st, 0L)) {
    stop("aws s3 sync failed (exit ", st, "): ", s3_dest)
  }
  invisible(NULL)
}

upload_zips_to_s3 <- function(files, r_minor, publish_contrib = TRUE) {
  bucket <- Sys.getenv("INZIGHT_RGTK2_S3_BUCKET", unset = "r.docker.stat.auckland.ac.nz")
  use_cli <- tolower(Sys.getenv("INZIGHT_RGTK2_S3_USE_CLI", unset = "")) %in% c("1", "true", "yes")

  if (publish_contrib) {
    contrib <- publish_contrib_dir(files, r_minor, root = getwd())
    dest <- sprintf("s3://%s/bin/windows/contrib/%s", bucket, r_minor)
    if (use_cli) {
      upload_with_cli(contrib, dest)
      message("Published win.binary repo at ", dest, "/")
    } else {
      if (!requireNamespace("aws.s3", quietly = TRUE)) {
        install.packages("aws.s3", repos = "https://cloud.r-project.org")
      }
      for (f in files) {
        key <- sprintf("bin/windows/contrib/%s/%s", r_minor, basename(f))
        aws.s3::put_object(
          file = normalizePath(f, winslash = "/", mustWork = TRUE),
          object = key,
          bucket = bucket,
          multipart = TRUE
        )
        message("Uploaded s3://", bucket, "/", key)
      }
      packs <- file.path(contrib, "PACKAGES")
      if (file.exists(packs)) {
        aws.s3::put_object(
          file = packs,
          object = sprintf("bin/windows/contrib/%s/PACKAGES", r_minor),
          bucket = bucket
        )
      }
    }
  }

  archive_base <- sprintf("s3://%s/static/rgtk2-windows/R-%s", bucket, r_minor)
  if (use_cli) {
    for (f in files) {
      dest <- paste0(archive_base, "/", basename(f))
      fp <- normalizePath(f, winslash = "/", mustWork = TRUE)
      argv <- c("s3", "cp", fp, dest)
      prof <- trimws(Sys.getenv("AWS_PROFILE", unset = ""))
      if (nzchar(prof)) argv <- c(argv, "--profile", prof)
      st <- system2(aws, argv)
      if (!identical(st, 0L)) stop("aws s3 cp failed for ", basename(f))
    }
    message("Archived copies at ", archive_base, "/")
    return(invisible(NULL))
  }

  if (!requireNamespace("aws.s3", quietly = TRUE)) {
    install.packages("aws.s3", repos = "https://cloud.r-project.org")
  }
  region <- trimws(Sys.getenv("AWS_DEFAULT_REGION", unset = ""))
  if (!nzchar(region)) {
    Sys.setenv(AWS_DEFAULT_REGION = "ap-southeast-2")
  }
  for (f in files) {
    key <- sprintf("static/rgtk2-windows/R-%s/%s", r_minor, basename(f))
    aws.s3::put_object(
      file = normalizePath(f, winslash = "/", mustWork = TRUE),
      object = key,
      bucket = bucket,
      multipart = TRUE
    )
    message("Archived s3://", bucket, "/", key)
  }
}

cat("Installing RGtk2 into curator library ...\n")
if (use_github_rgtk2) {
  ref <- Sys.getenv("INZIGHT_RGTK2_GITHUB", unset = "tmelliott/RGtk2/RGtk2")
  message("No local RGtk2 source; installing from GitHub: ", ref)
  remotes::install_github(
    ref,
    lib = lib,
    upgrade = "never",
    INSTALL_opts = c("--no-multiarch", "--no-test-load")
  )
} else {
  remotes::install_local(
    rgtk2_src,
    lib = lib,
    dependencies = NA,
    upgrade = "never",
    INSTALL_opts = c("--no-multiarch", "--no-test-load")
  )
}

gtk_zip <- file.path(tempdir(), "gtk-bundle-curator.zip")
download.file(gtk_url, destfile = gtk_zip, mode = "wb")
gtk_stage <- file.path(tempdir(), "gtk-unpack")
unlink(gtk_stage, recursive = TRUE)
dir.create(gtk_stage)
unzip(gtk_zip, exdir = gtk_stage)
file.remove(gtk_zip)

rgtk2_inst <- file.path(lib, "RGtk2")
subs <- dir(gtk_stage, full.names = TRUE)
subs <- subs[!is.na(file.info(subs)$isdir) & file.info(subs)$isdir]
from <- if (length(subs) == 1L) subs else gtk_stage
layout_unpacked_gtk_for_rgtk2(from, rgtk2_inst)

z1 <- zip_win_binary("RGtk2", lib, output_dir)

cat("Installing cairoDevice ...\n")
remotes::install_local(
  cairo_src,
  lib = lib,
  dependencies = NA,
  upgrade = "never",
  INSTALL_opts = c("--no-multiarch", "--no-test-load")
)

r_minor <- paste(
  strsplit(as.character(getRversion()), "\\.")[[1]][1:2],
  collapse = "."
)

z2 <- zip_win_binary("cairoDevice", lib, output_dir)

message("\n=== Artifacts ===\n", z1, "\n", z2)

want_s3 <- any(args == "--upload-s3") ||
  tolower(Sys.getenv("INZIGHT_RGTK2_UPLOAD_S3", unset = "")) %in% c("1", "true", "yes")
no_contrib <- any(args == "--no-publish-contrib")
if (want_s3) {
  upload_zips_to_s3(c(z1, z2), r_minor, publish_contrib = !no_contrib)
} else {
  contrib <- publish_contrib_dir(c(z1, z2), r_minor, root = getwd())
  message("\nLocal contrib dir: ", contrib)
  message(
    "\nOptional S3 upload: add to .env INZIGHT_RGTK2_UPLOAD_S3=1 and AWS_* keys\n",
    "or pass --upload-s3. Use INZIGHT_RGTK2_S3_USE_CLI=1 for aws CLI (e.g. AWS_PROFILE=saml).\n",
    "Upload publishes to bin/windows/contrib/<R minor>/ (install_gtk.R) plus static archive.\n"
  )
}
