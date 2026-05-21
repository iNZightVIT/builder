#!/usr/bin/env Rscript
# Copy GTK runtime into installed RGtk2 (Windows installer CI).
if (.Platform$OS.type != "windows") {
  stop("layout_rgtk2_gtk_runtime_ci.R is Windows-only", call. = FALSE)
}

root <- Sys.getenv("INZIGHT_BUILDER_ROOT", unset = getwd())
source(file.path(root, "R", "gtk_win64.R"), local = TRUE)

lib <- Sys.getenv("R_LIBS_USER", unset = "")
if (!nzchar(lib)) {
  lib <- .libPaths()[1]
}
gtk_bin <- layout_gtk_runtime_for_lib(lib)
ghp <- Sys.getenv("GITHUB_PATH", unset = "")
if (nzchar(ghp)) {
  write(gtk_bin, file = ghp, append = TRUE)
}
message("GTK runtime at ", gtk_bin)
