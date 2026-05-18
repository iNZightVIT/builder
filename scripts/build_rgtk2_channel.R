# Build RGtk2/cairoDevice from source for a channel: install into R_LIBS_USER,
# write gtk-free win.binary zips into channel staging contrib.
if (sys.nframe() == 0L) {
  source("channels/_shared.R", local = TRUE)
  channel <- parse_cli_channel(commandArgs(TRUE))
  r_minor <- r_minor_version()
  out_dir <- channel_contrib_dir(channel, r_minor)
  lib <- Sys.getenv("R_LIBS_USER", unset = .libPaths()[1])
  root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

  argv <- c(
    "scripts/build_rgtk2_windows_artifacts.R",
    paste0("--output-dir=", out_dir),
    paste0("--lib=", lib),
    paste0("--root=", root),
    "--gtk-free"
  )
  status <- system2("Rscript", argv)
  if (!identical(status, 0L)) {
    stop("build_rgtk2_windows_artifacts.R failed (exit ", status, ")", call. = FALSE)
  }
}
