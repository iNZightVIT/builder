#!/usr/bin/env Rscript
# Prefer published win.binary RGtk2/cairoDevice; compile from submodules only if missing.
root <- Sys.getenv("INZIGHT_BUILDER_ROOT", unset = getwd())
source(file.path(root, "R", "rgtk2_cairo_install.R"), local = TRUE)

lib <- Sys.getenv("R_LIBS_USER", unset = "")
if (!nzchar(lib)) {
  lib <- .libPaths()[1]
}
dir.create(lib, recursive = TRUE, showWarnings = FALSE)

methods <- install_rgtk_cairo_with_fallback(lib, root = root)
message("RGtk2 via ", methods$RGtk2, "; cairoDevice via ", methods$cairoDevice)

# gtk-free published zips need the runtime laid out for Check / gWidgets use.
if (.Platform$OS.type == "windows") {
  layout_gtk_runtime_for_lib(lib)
}
