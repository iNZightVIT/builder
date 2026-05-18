# Build missing win.binary zips for a channel (excludes RGtk2/cairoDevice).
source("channels/_shared.R", local = TRUE)
source("R/channel_resolve.R", local = TRUE)

BINARY_DENYLIST <- c("RGtk2", "cairoDevice")

`%||%` <- function(x, y) if (is.null(x)) y else x

download_source_dir <- function(spec) {
  if (grepl("/", spec) && requireNamespace("pak", quietly = TRUE)) {
    dl <- pak::pkg_download(spec)
    st <- dl$download_status[[1]]
    path <- st$local$path %||% st$local$package_path
    if (is.null(path) || !dir.exists(path)) {
      stop("pak could not download source for ", spec)
    }
    return(normalizePath(path, winslash = "/", mustWork = TRUE))
  }

  pkg <- pkg_name_from_spec(spec)
  td <- tempfile("cran-src-")
  dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  ap <- available.packages(repos = DEFAULT_CRAN, type = "source")
  if (!pkg %in% rownames(ap)) {
    stop("No CRAN source for ", pkg)
  }
  utils::download.packages(pkg, destdir = td, repos = DEFAULT_CRAN, type = "source")
  tgz <- list.files(td, pattern = "\\.tar\\.gz$", full.names = TRUE)
  if (length(tgz) != 1L) {
    stop("Expected one source tarball for ", pkg)
  }
  unpack <- tempfile("cran-unpack-")
  dir.create(unpack)
  utils::untar(tgz, exdir = unpack)
  dirs <- list.dirs(unpack, recursive = FALSE, full.names = TRUE)
  if (length(dirs) != 1L) {
    stop("Unexpected unpack layout for ", pkg)
  }
  normalizePath(dirs[[1]], winslash = "/", mustWork = TRUE)
}

build_channel_binaries <- function(channel) {
  deps <- read_channel_deps(channel)

  contrib_dir <- channel_contrib_dir(channel)
  dir.create(contrib_dir, recursive = TRUE, showWarnings = FALSE)

  resolved <- resolve_channel_packages(deps)
  pkg_names <- unique(vapply(resolved, pkg_name_from_spec, character(1)))
  pkg_names <- pkg_names[!pkg_names %in% BINARY_DENYLIST]

  if (file.exists(file.path(contrib_dir, "PACKAGES"))) {
    current <- read.dcf(file.path(contrib_dir, "PACKAGES"))
    current <- current[, c("Package", "Version")]
  } else {
    current <- matrix(character(0), nrow = 0, ncol = 2,
      dimnames = list(NULL, c("Package", "Version")))
  }

  installed <- installed.packages()[, c("Package", "Version"), drop = FALSE]

  to_build <- character(0)
  for (pkg in pkg_names) {
    if (!pkg %in% rownames(installed)) {
      warning("Package not installed, skipping binary build: ", pkg, call. = FALSE)
      next
    }
    new_ver <- installed[pkg, "Version"]
    if (!pkg %in% current[, "Package"]) {
      to_build <- c(to_build, pkg)
      next
    }
    cur_ver <- current[current[, "Package"] == pkg, "Version"]
    if (length(cur_ver) != 1L) {
      to_build <- c(to_build, pkg)
      next
    }
    if (numeric_version(new_ver) > numeric_version(cur_ver)) {
      to_build <- c(to_build, pkg)
    }
  }

  if (!length(to_build)) {
    message("No channel binaries need building for ", channel)
    tools::write_PACKAGES(contrib_dir, type = "win.binary", verbose = TRUE)
    return(invisible(contrib_dir))
  }

  message("Building win.binary for: ", paste(to_build, collapse = ", "))

  spec_for_pkg <- function(pkg) {
    hits <- resolved[vapply(resolved, function(s) pkg_name_from_spec(s) == pkg, logical(1))]
    if (length(hits)) hits[[1]] else pkg
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)

  for (pkg in to_build) {
    spec <- spec_for_pkg(pkg)
    message(" === Building ", pkg, " (", spec, ") ===")
    srcdir <- download_source_dir(spec)
    setwd(tempdir())
    status <- system2("R", c("CMD", "build", "--no-build-vignettes", shQuote(srcdir)))
    if (status != 0) stop("R CMD build failed for ", pkg)

    tgz <- list.files(pattern = paste0("^", pkg, "_.*\\.tar\\.gz$"))
    if (length(tgz) != 1L) {
      stop("Build tarball not found for ", pkg)
    }

    status <- system2("R", c("CMD", "INSTALL", "--no-multiarch", "-l", ".", shQuote(tgz)))
    if (status != 0) stop("R CMD INSTALL failed for ", pkg)

    zipname <- sub("\\.tar\\.gz$", ".zip", tgz)
    utils::zip(zipname, pkg)

    old <- list.files(contrib_dir, pattern = paste0("^", pkg, "_"))
    if (length(old)) unlink(file.path(contrib_dir, old))

    file.copy(zipname, contrib_dir, overwrite = TRUE)
    unlink(c(tgz, zipname))
    unlink(pkg, recursive = TRUE)
  }

  setwd(old_wd)
  tools::write_PACKAGES(contrib_dir, type = "win.binary", verbose = TRUE)
  message("Wrote PACKAGES in ", contrib_dir)
  invisible(contrib_dir)
}

if (sys.nframe() == 0L) {
  build_channel_binaries(parse_cli_channel(commandArgs(TRUE)))
}
