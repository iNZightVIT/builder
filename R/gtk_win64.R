# Windows x64 GTK bundle: compile-time devkit (C:/GTK64) and runtime under RGtk2/gtk/x64/.

default_gtk_bundle_url <- function() {
  Sys.getenv(
    "INZIGHT_GTK_BUNDLE_URL",
    unset = "https://ftp.gnome.org/pub/gnome/binaries/win64/gtk+/2.22/gtk+-bundle_2.22.1-20101229_win64.zip"
  )
}

assert_windows_x64 <- function() {
  if (.Platform$OS.type != "windows") {
    return(invisible(TRUE))
  }
  arch <- .Platform$r_arch
  if (!identical(arch, "x64") && !grepl("x64", R.version$arch, fixed = TRUE)) {
    stop(
      "RGtk2/cairo source build requires 64-bit R (r_arch=",
      arch,
      ", R.version$arch=",
      R.version$arch,
      ")",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

gtk64_devkit_ready <- function(gtk_root) {
  file.exists(file.path(gtk_root, "bin", "libgtk-win32-2.0-0.dll")) &&
    file.exists(file.path(gtk_root, "include", "gtk-2.0", "gtk", "gtk.h"))
}

download_and_unpack_gtk_bundle <- function(gtk_url = default_gtk_bundle_url()) {
  td <- tempfile("gtk-bundle-")
  dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  gtk_zip <- file.path(td, "gtk-bundle.zip")
  message("Downloading GTK bundle: ", gtk_url)
  status <- download.file(gtk_url, destfile = gtk_zip, mode = "wb")
  if (status != 0) {
    stop("GTK bundle download failed: ", gtk_url, call. = FALSE)
  }
  gtk_stage <- file.path(td, "unpack")
  dir.create(gtk_stage)
  unzip(gtk_zip, exdir = gtk_stage)
  subs <- dir(gtk_stage, full.names = TRUE)
  subs <- subs[!is.na(file.info(subs)$isdir) & file.info(subs)$isdir]
  if (length(subs) == 1L) subs[[1]] else gtk_stage
}

copy_gtk_tree_into_root <- function(from, gtk_root) {
  if (!dir.exists(gtk_root)) {
    dir.create(gtk_root, recursive = TRUE)
  }
  items <- list.files(from, full.names = TRUE, all.files = FALSE)
  if (!length(items)) {
    stop("empty GTK tree at ", from, call. = FALSE)
  }
  for (item in items) {
    dest <- file.path(gtk_root, basename(item))
    if (dir.exists(dest)) {
      unlink(dest, recursive = TRUE)
    } else if (file.exists(dest)) {
      file.remove(dest)
    }
    ok <- file.copy(item, gtk_root, recursive = TRUE, copy.date = TRUE)
    if (!isTRUE(ok)) {
      stop("could not copy ", item, " into ", gtk_root, call. = FALSE)
    }
  }
  invisible(gtk_root)
}

ensure_gtk64_devkit <- function(
    gtk_root = Sys.getenv("INZIGHT_GTK64_ROOT", unset = "C:/GTK64"),
    gtk_url = default_gtk_bundle_url()) {
  assert_windows_x64()
  gtk_root <- gsub("\\\\", "/", gtk_root)
  if (!gtk64_devkit_ready(gtk_root)) {
    message("Installing GTK64 devkit at ", gtk_root)
    from <- download_and_unpack_gtk_bundle(gtk_url)
    copy_gtk_tree_into_root(from, gtk_root)
    if (!gtk64_devkit_ready(gtk_root)) {
      stop("GTK64 devkit incomplete after install: ", gtk_root, call. = FALSE)
    }
  } else {
    message("GTK64 devkit already present at ", gtk_root)
  }
  Sys.setenv(GTK_PATH = gtk_root, WIN = "64")
  invisible(gtk_root)
}

## Move unpacked GTK tree into <rgtk2_root>/gtk/x64/ (cross-drive safe on Windows).
layout_unpacked_gtk_for_rgtk2 <- function(from, rgtk2_root, remove_source = FALSE) {
  gtk_dest <- file.path(rgtk2_root, "gtk", "x64")
  dir.create(file.path(rgtk2_root, "gtk"), recursive = TRUE, showWarnings = FALSE)
  if (dir.exists(gtk_dest)) {
    unlink(gtk_dest, recursive = TRUE)
  }
  dir.create(gtk_dest, recursive = TRUE, showWarnings = FALSE)
  items <- list.files(from, full.names = TRUE, all.files = TRUE)
  items <- items[!basename(items) %in% c(".", "..")]
  if (!length(items)) {
    stop("empty GTK unpack at ", from, call. = FALSE)
  }
  ok <- file.copy(items, gtk_dest, recursive = TRUE, copy.date = TRUE)
  if (length(ok) != length(items) || !all(ok)) {
    stop("could not copy GTK bundle into ", gtk_dest, call. = FALSE)
  }
  if (remove_source) {
    unlink(from, recursive = TRUE)
  }
  invisible(gtk_dest)
}

layout_gtk_runtime_for_lib <- function(
    lib,
    gtk_url = default_gtk_bundle_url(),
    gtk_root = Sys.getenv("INZIGHT_GTK64_ROOT", unset = "C:/GTK64")) {
  rgtk2_root <- file.path(lib, "RGtk2")
  gtk_bin <- file.path(rgtk2_root, "gtk", "x64", "bin")
  if (dir.exists(gtk_bin)) {
    Sys.setenv(GTK_PATH = file.path(rgtk2_root, "gtk", "x64"))
    return(invisible(gtk_bin))
  }
  if (gtk64_devkit_ready(gtk_root)) {
    layout_unpacked_gtk_for_rgtk2(gtk_root, rgtk2_root, remove_source = FALSE)
  } else {
    from <- download_and_unpack_gtk_bundle(gtk_url)
    layout_unpacked_gtk_for_rgtk2(from, rgtk2_root, remove_source = TRUE)
  }
  Sys.setenv(GTK_PATH = file.path(rgtk2_root, "gtk", "x64"))
  invisible(gtk_bin)
}
