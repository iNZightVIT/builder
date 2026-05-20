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

default_lib <- Sys.getenv("R_LIBS_USER", unset = "")
if (!nzchar(default_lib)) {
  default_lib <- .libPaths()[1]
}
lib <- get_arg("lib", default_lib)
if (!dir.exists(lib)) dir.create(lib, recursive = TRUE)
lib <- normalizePath(lib, winslash = "/", mustWork = TRUE)
gtk_free <- "--gtk-free" %in% args
zip_only <- "--zip-only" %in% args

repo_root <- get_arg("root", Sys.getenv("INZIGHT_BUILDER_ROOT", unset = getwd()))
source(file.path(repo_root, "R", "rgtk2_cairo_install.R"), local = TRUE)

ensure_remotes()
assert_windows_x64()

zip_win_binary <- function(pkg, lib, out_dir, gtk_free = FALSE) {
  desc <- read.dcf(file.path(lib, pkg, "DESCRIPTION"))
  ver <- desc[1, "Version"]
  zipname <- sprintf("%s_%s.zip", pkg, ver)
  zpath <- file.path(out_dir, zipname)
  if (file.exists(zpath)) file.remove(zpath)

  if (gtk_free && pkg == "RGtk2") {
    staging <- tempfile("rgtk2-zip-")
    dir.create(staging)
    on.exit(unlink(staging, recursive = TRUE), add = TRUE)
    dest <- file.path(staging, pkg)
    file.copy(file.path(lib, pkg), staging, recursive = TRUE)
    gtk_dir <- file.path(dest, "gtk")
    if (dir.exists(gtk_dir)) unlink(gtk_dir, recursive = TRUE)
    ow <- getwd()
    on.exit(setwd(ow), add = TRUE)
    setwd(staging)
    utils::zip(zpath, pkg)
    return(normalizePath(zpath, winslash = "/", mustWork = TRUE))
  }

  ow <- getwd()
  on.exit(setwd(ow), add = TRUE)
  setwd(lib)
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

if (zip_only) {
  for (pkg in c("RGtk2", "cairoDevice")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(
        pkg,
        " is not installed; install first or omit --zip-only",
        call. = FALSE
      )
    }
  }
  message("Zipping installed RGtk2 and cairoDevice (--zip-only)")
} else {
  gtk_root <- ensure_gtk64_devkit()

  cat("Installing RGtk2 into curator library ...\n")
  install_rgtk2_from_source(lib, repo_root)
  layout_gtk_runtime_for_lib(lib, gtk_root = gtk_root)

  cat("Installing cairoDevice ...\n")
  install_cairodevice_from_source(lib, repo_root)
}

z1 <- zip_win_binary("RGtk2", lib, output_dir, gtk_free = gtk_free)

r_minor <- paste(
  strsplit(as.character(getRversion()), "\\.")[[1]][1:2],
  collapse = "."
)

z2 <- zip_win_binary("cairoDevice", lib, output_dir, gtk_free = gtk_free)

message("\n=== Artifacts ===\n", z1, "\n", z2)

if (dir.exists(output_dir)) {
  tools::write_PACKAGES(output_dir, type = "win.binary", verbose = TRUE)
  message("Wrote PACKAGES in ", output_dir)
}

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
