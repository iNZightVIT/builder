#!/usr/bin/env Rscript
# Install GTK devkit for Windows CI (RGtk2/cairoDevice compile + runtime PATH).
if (.Platform$OS.type != "windows") {
  stop("install_gtk_ci.R is Windows-only", call. = FALSE)
}

root <- Sys.getenv("INZIGHT_BUILDER_ROOT", unset = getwd())
source(file.path(root, "R", "gtk_win64.R"), local = TRUE)

gtk_root <- Sys.getenv("GTK_PATH", unset = "")
if (!nzchar(gtk_root)) {
  gtk_root <- file.path(Sys.getenv("RUNNER_TEMP", unset = tempdir()), "GTK", "x64")
}
gtk_root <- normalizePath(gtk_root, winslash = "/", mustWork = FALSE)
dir.create(gtk_root, recursive = TRUE, showWarnings = FALSE)

ensure_gtk64_devkit(gtk_root = gtk_root)
gtk_bin <- file.path(gtk_root, "bin")
if (!file.exists(file.path(gtk_bin, "libgtk-win32-2.0-0.dll"))) {
  stop("GTK devkit incomplete at ", gtk_root, call. = FALSE)
}

ghp <- Sys.getenv("GITHUB_PATH", unset = "")
if (nzchar(ghp)) {
  write(gtk_bin, file = ghp, append = TRUE)
}
message("GTK devkit ready at ", gtk_root)
