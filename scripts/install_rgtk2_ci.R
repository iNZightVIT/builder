#!/usr/bin/env Rscript
# Install RGtk2 and cairoDevice from builder submodules (Windows CI).
root <- Sys.getenv("INZIGHT_BUILDER_ROOT", unset = getwd())
source(file.path(root, "R", "rgtk2_cairo_install.R"), local = TRUE)

lib <- Sys.getenv("R_LIBS_USER", unset = "")
if (!nzchar(lib)) {
  lib <- .libPaths()[1]
}
dir.create(lib, recursive = TRUE, showWarnings = FALSE)

if (.Platform$OS.type == "windows") {
  gtk_root <- Sys.getenv("INZIGHT_GTK64_ROOT", unset = Sys.getenv("GTK_PATH", unset = ""))
  if (!nzchar(gtk_root)) {
    stop("GTK_PATH or INZIGHT_GTK64_ROOT must be set on Windows", call. = FALSE)
  }
  ensure_gtk64_devkit(gtk_root = gtk_root)
}

install_rgtk2_from_source(lib, root = root)
install_cairodevice_from_source(lib, root = root)
message("RGtk2 and cairoDevice installed in ", lib)
