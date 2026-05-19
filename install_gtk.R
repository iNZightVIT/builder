# if windows
if (.Platform$OS.type != "windows") {
  stop("install_gtk.R is only supported on Windows")
}

GTK_PATH <- Sys.getenv("GTK_PATH")
if (!nzchar(GTK_PATH)) {
  stop("GTK_PATH is not set")
}

if (!dir.exists(GTK_PATH)) {
  dir.create(GTK_PATH, recursive = TRUE)
}

cat("Downloading gtk ...\n")
gtk_url <- "https://inzight.nz/data/gtk+-bundle_2.22.1-20101229_win64.zip"

# Downloading gtk
download.file(gtk_url, destfile = "gtk.zip")
dir.create("gtk")
unzip("gtk.zip", exdir = "gtk")
file.remove("gtk.zip")


Sys.setenv(GTK_PATH = file.path(getwd(), "gtk"))

if (!requireNamespace("remotes", quietly = TRUE)) {
  cat("Installing remotes ...\n")
  install.packages("remotes")
}
if (!requireNamespace("RGtk2", quietly = TRUE)) {
  cat("Installing RGtk2 ...\n")
  if (.Platform$OS.type == "windows") {
    remotes::install_cran("RGtk2",
      INSTALL_opts = "--no-test-load"
    )
  }
}
if (!requireNamespace("cairoDevice", quietly = TRUE)) {
  cat("Installing cairoDevice ...\n")
  install.packages("cairoDevice",
    type = "source",
    build = FALSE
  )
}

if (.Platform$OS.type == "windows") {
  if (!file.exists(file.path(system.file("", package = "RGtk2"), "gtk"))) {
    cat("Moving gtk binary to RGtk2 ...\n")
    dir.create(file.path(system.file("", package = "RGtk2"), "gtk"))
    file.rename("gtk", file.path(system.file("", package = "RGtk2"), "gtk", "x64"))
  } else {
    unlink("gtk", recursive = TRUE)
  }
}
