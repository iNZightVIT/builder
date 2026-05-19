# Build missing win.binary zips for a channel (excludes RGtk2/cairoDevice).
source("channels/_shared.R", local = TRUE)
source("R/channel_resolve.R", local = TRUE)

BINARY_DENYLIST <- c("RGtk2", "cairoDevice")

`%||%` <- function(x, y) if (is.null(x)) y else x

find_package_root <- function(dir) {
  desc <- list.files(dir, pattern = "^DESCRIPTION$", recursive = TRUE, full.names = TRUE)
  if (!length(desc)) {
    return(NULL)
  }
  normalizePath(dirname(desc[[1L]]), winslash = "/", mustWork = TRUE)
}

untar_package_root <- function(archive) {
  unpack <- tempfile("src-unpack-")
  dir.create(unpack)
  if (grepl("\\.zip$", archive, ignore.case = TRUE)) {
    utils::unzip(archive, exdir = unpack)
  } else {
    utils::untar(archive, exdir = unpack)
  }
  root <- find_package_root(unpack)
  if (is.null(root)) {
    stop("No DESCRIPTION found after unpacking ", archive)
  }
  root
}

download_zipball <- function(url, dest_dir) {
  archive <- file.path(dest_dir, "source.zip")
  utils::download.file(url, archive, mode = "wb", quiet = TRUE)
  untar_package_root(archive)
}

download_source_dir <- function(spec) {
  pkg <- pkg_name_from_spec(spec)

  if (requireNamespace("pak", quietly = TRUE)) {
    dest_root <- tempfile("pak-dl-")
    dir.create(dest_root)
    on.exit(unlink(dest_root, recursive = TRUE), add = TRUE)

    dl <- pak::pkg_download(spec, dest_dir = dest_root)
    ft <- dl$fulltarget[[1L]] %||% dl$fulltarget[1L]

    if (nzchar(ft) && file.exists(ft)) {
      return(untar_package_root(ft))
    }

    tree <- paste0(ft, "-t")
    if (nzchar(ft) && dir.exists(tree)) {
      root <- find_package_root(tree)
      if (!is.null(root)) {
        return(root)
      }
    }

    srcs <- dl$sources[[1L]]
    if (length(srcs) && nzchar(srcs[[1L]])) {
      return(download_zipball(srcs[[1L]], dest_root))
    }
  }

  if (pkg %in% rownames(installed.packages())) {
    desc <- utils::packageDescription(pkg)
    if (!is.na(desc$RemoteType) && desc$RemoteType == "github") {
      sha <- desc$RemoteSha
      url <- sprintf(
        "https://api.github.com/repos/%s/%s/zipball/%s",
        desc$RemoteUsername,
        desc$RemoteRepo,
        sha
      )
      td <- tempfile("gh-src-")
      dir.create(td)
      on.exit(unlink(td, recursive = TRUE), add = TRUE)
      return(download_zipball(url, td))
    }
  }

  td <- tempfile("cran-src-")
  dir.create(td)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)
  ap <- available.packages(repos = DEFAULT_CRAN, type = "source")
  if (!pkg %in% rownames(ap)) {
    stop("No source found for ", spec, " (not in pak download, remotes, or CRAN)")
  }
  utils::download.packages(pkg, destdir = td, repos = DEFAULT_CRAN, type = "source")
  tgz <- list.files(td, pattern = "\\.tar\\.gz$", full.names = TRUE)
  if (length(tgz) != 1L) {
    stop("Expected one source tarball for ", pkg)
  }
  untar_package_root(tgz[[1L]])
}

build_channel_binaries <- function(channel) {
  deps <- read_channel_deps(channel)

  contrib_dir <- channel_contrib_dir(channel)
  dir.create(contrib_dir, recursive = TRUE, showWarnings = FALSE)
  # Absolute path: setwd(tempdir()) during R CMD build/install must not relocate output.
  contrib_dir <- normalizePath(contrib_dir, winslash = "/", mustWork = FALSE)

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
  message("Output directory: ", contrib_dir)

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
    status <- system2(
      "R",
      c("CMD", "build", "--no-build-vignettes", "--no-manual", shQuote(srcdir))
    )
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
