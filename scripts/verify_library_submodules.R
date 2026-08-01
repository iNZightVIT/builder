#!/usr/bin/env Rscript
# Confirm gWidgets library/ submodules are present and visible to R (Windows CI).
pkgs <- c("gWidgets", "gWidgetsRGtk2", "gWidgets2", "gWidgets2RGtk2")
root <- Sys.getenv("INZIGHT_BUILDER_ROOT", unset = "")
if (!nzchar(root)) {
  root <- getwd()
}
root <- normalizePath(root, winslash = "/", mustWork = TRUE)
paths <- file.path(root, "library", pkgs, "DESCRIPTION")
missing <- pkgs[!file.exists(paths)]
if (length(missing)) {
  stop(
    "Missing library submodule(s): ", paste(missing, collapse = ", "),
    "\nroot: ", root,
    "\nwd: ", getwd(),
    call. = FALSE
  )
}
cat(paste(paths, collapse = "\n"), "\n", sep = "")
