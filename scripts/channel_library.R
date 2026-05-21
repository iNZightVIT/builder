# Install and build win.binary zips for bundled library/ submodules (gWidgets stack).
source("channels/_shared.R", local = TRUE)

library_source_dir <- function(pkg) {
  src <- file.path("library", pkg)
  if (!file.exists(file.path(src, "DESCRIPTION"))) {
    stop("Missing library submodule: ", src, call. = FALSE)
  }
  normalizePath(src, winslash = "/", mustWork = TRUE)
}

install_channel_library <- function() {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes", repos = DEFAULT_CRAN)
  }
  opts <- c("--no-multiarch", "--no-test-load", "--no-docs")
  for (pkg in CHANNEL_LIBRARY_PKGS) {
    src <- library_source_dir(pkg)
    message("Installing ", pkg, " from ", src)
    remotes::install_local(
      src,
      upgrade = "never",
      INSTALL_opts = opts
    )
  }
  invisible(CHANNEL_LIBRARY_PKGS)
}

build_win_binary_zip <- function(pkg, srcdir, contrib_dir) {
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  td <- tempfile("lib-build-")
  dir.create(td)
  setwd(td)

  status <- system2(
    "R",
    c("CMD", "build", "--no-build-vignettes", "--no-manual", shQuote(srcdir))
  )
  if (status != 0) {
    stop("R CMD build failed for ", pkg, call. = FALSE)
  }

  tgz <- list.files(pattern = paste0("^", pkg, "_.*\\.tar\\.gz$"))
  if (length(tgz) != 1L) {
    stop("Build tarball not found for ", pkg, call. = FALSE)
  }

  status <- system2("R", c("CMD", "INSTALL", "--no-multiarch", "-l", ".", shQuote(tgz)))
  if (status != 0) {
    stop("R CMD INSTALL failed for ", pkg, call. = FALSE)
  }

  zipname <- sub("\\.tar\\.gz$", ".zip", tgz)
  utils::zip(zipname, pkg)

  old <- list.files(contrib_dir, pattern = paste0("^", pkg, "_"))
  if (length(old)) {
    unlink(file.path(contrib_dir, old))
  }
  file.copy(zipname, contrib_dir, overwrite = TRUE)
  unlink(c(tgz, zipname))
  unlink(pkg, recursive = TRUE)
  invisible(file.path(contrib_dir, zipname))
}

build_channel_library <- function(channel) {
  contrib_dir <- channel_contrib_dir(channel)
  dir.create(contrib_dir, recursive = TRUE, showWarnings = FALSE)
  contrib_dir <- normalizePath(contrib_dir, winslash = "/", mustWork = FALSE)

  if (file.exists(file.path(contrib_dir, "PACKAGES"))) {
    current <- read.dcf(file.path(contrib_dir, "PACKAGES"))
    current <- current[, c("Package", "Version")]
  } else {
    current <- matrix(character(0), nrow = 0, ncol = 2,
      dimnames = list(NULL, c("Package", "Version")))
  }

  to_build <- character(0)
  for (pkg in CHANNEL_LIBRARY_PKGS) {
    srcdir <- library_source_dir(pkg)
    desc <- read.dcf(file.path(srcdir, "DESCRIPTION"))
    new_ver <- desc[1, "Version"]
    if (!pkg %in% current[, "Package"]) {
      to_build <- c(to_build, pkg)
      next
    }
    cur_ver <- current[current[, "Package"] == pkg, "Version"]
    if (length(cur_ver) != 1L ||
        numeric_version(new_ver) > numeric_version(cur_ver)) {
      to_build <- c(to_build, pkg)
    }
  }

  if (!length(to_build)) {
    message("No library bundle binaries need building for ", channel)
    if (file.exists(file.path(contrib_dir, "PACKAGES"))) {
      tools::write_PACKAGES(contrib_dir, type = "win.binary", verbose = TRUE)
    }
    return(invisible(contrib_dir))
  }

  message("Building library win.binary for: ", paste(to_build, collapse = ", "))
  for (pkg in to_build) {
    message(" === Building ", pkg, " (library/) ===")
    build_win_binary_zip(pkg, library_source_dir(pkg), contrib_dir)
  }

  tools::write_PACKAGES(contrib_dir, type = "win.binary", verbose = TRUE)
  message("Wrote PACKAGES in ", contrib_dir)
  invisible(contrib_dir)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  if (any(args == "--install")) {
    install_channel_library()
  } else if (any(grepl("^--channel=", args))) {
    build_channel_library(parse_cli_channel(args))
  } else {
    stop("Usage: Rscript scripts/channel_library.R --install\n",
      "       Rscript scripts/channel_library.R --channel=<name> --build",
      call. = FALSE
    )
  }
}
