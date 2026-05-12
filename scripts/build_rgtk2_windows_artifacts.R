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

if (!nzchar(rgtk2_src)) {
  p <- file.path(repo_root, "library", "RGtk2")
  if (dir.exists(p)) rgtk2_src <- p
}
if (!nzchar(cairo_src)) {
  p <- file.path(repo_root, "library", "cairoDevice")
  if (dir.exists(p)) cairo_src <- p
}
if (!nzchar(rgtk2_src) || !nzchar(cairo_src)) {
  stop(
    "Set INZIGHT_RGTK2_SOURCE and INZIGHT_CAIRODEVICE_SOURCE to package source dirs, ",
    "or run from the builder repo with library/RGtk2 and library/cairoDevice present."
  )
}

if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", repos = "https://cloud.r-project.org")
}

gtk_url <- Sys.getenv(
  "INZIGHT_GTK_BUNDLE_URL",
  unset = "https://inzight.nz/data/gtk+-bundle_2.22.1-20101229_win64.zip"
)

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

upload_zips_to_s3 <- function(files, r_minor) {
  bucket <- Sys.getenv("INZIGHT_RGTK2_S3_BUCKET", unset = "r.docker.stat.auckland.ac.nz")
  base <- sprintf("s3://%s/static/rgtk2-windows/R-%s", bucket, r_minor)
  use_cli <- tolower(Sys.getenv("INZIGHT_RGTK2_S3_USE_CLI", unset = "")) %in% c("1", "true", "yes")

  if (use_cli) {
    aws <- Sys.which("aws")
    if (!nzchar(aws)) {
      stop("INZIGHT_RGTK2_S3_USE_CLI is set but AWS CLI (`aws`) not on PATH.")
    }
    prof <- trimws(Sys.getenv("AWS_PROFILE", unset = ""))
    for (f in files) {
      dest <- paste0(base, "/", basename(f))
      fp <- normalizePath(f, winslash = "/", mustWork = TRUE)
      argv <- c("s3", "cp", fp, dest)
      if (nzchar(prof)) {
        argv <- c(argv, "--profile", prof)
      }
      message(paste(c(shQuote(aws, type = "cmd"), argv), collapse = " "))
      st <- system2(aws, argv)
      if (!identical(st, 0L)) {
        stop("aws s3 cp failed for ", basename(f), " (exit ", st, ")")
      }
    }
    message("Uploaded to ", base, "/")
    return(invisible(NULL))
  }

  if (!requireNamespace("aws.s3", quietly = TRUE)) {
    ip <- list(pkgs = "aws.s3", repos = "https://cloud.r-project.org")
    if (.Platform$OS.type == "windows") {
      ip$INSTALL_opts <- "--no-multiarch"
    }
    do.call(install.packages, ip)
  }

  region <- trimws(Sys.getenv("AWS_DEFAULT_REGION", unset = ""))
  if (!nzchar(region)) {
    region <- "ap-southeast-2"
    Sys.setenv(AWS_DEFAULT_REGION = region)
  }

  for (f in files) {
    key <- sprintf("static/rgtk2-windows/R-%s/%s", r_minor, basename(f))
    fp <- normalizePath(f, winslash = "/", mustWork = TRUE)
    aws.s3::put_object(
      file = fp,
      object = key,
      bucket = bucket,
      multipart = TRUE
    )
    message("Uploaded s3://", bucket, "/", key)
  }
  message("Done: ", base, "/")
}

cat("Installing RGtk2 into curator library ...\n")
remotes::install_local(
  rgtk2_src,
  lib = lib,
  dependencies = NA,
  upgrade = "never",
  INSTALL_opts = c("--no-multiarch", "--no-test-load")
)

gtk_zip <- file.path(tempdir(), "gtk-bundle-curator.zip")
download.file(gtk_url, destfile = gtk_zip, mode = "wb")
gtk_stage <- file.path(tempdir(), "gtk-unpack")
unlink(gtk_stage, recursive = TRUE)
dir.create(gtk_stage)
unzip(gtk_zip, exdir = gtk_stage)
file.remove(gtk_zip)

rgtk2_inst <- file.path(lib, "RGtk2")
gtk_dest <- file.path(rgtk2_inst, "gtk", "x64")
if (dir.exists(gtk_dest)) unlink(gtk_dest, recursive = TRUE)
dir.create(file.path(rgtk2_inst, "gtk"), recursive = TRUE)
subs <- dir(gtk_stage, full.names = TRUE)
subs <- subs[!is.na(file.info(subs)$isdir) & file.info(subs)$isdir]
from <- if (length(subs) == 1L) subs else gtk_stage
file.rename(from, gtk_dest)

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
if (want_s3) {
  upload_zips_to_s3(c(z1, z2), r_minor)
} else {
  message(
    "\nOptional S3 upload: add to .env INZIGHT_RGTK2_UPLOAD_S3=1 and AWS_* keys\n",
    "(aws.s3 / https://github.com/cloudyr/aws.s3 ), or pass --upload-s3.\n",
    "Use INZIGHT_RGTK2_S3_USE_CLI=1 to use the `aws` CLI instead (e.g. AWS_PROFILE).\n"
  )
}
