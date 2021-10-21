# build packages
os <- Sys.getenv("OS_TYPE")
sources <- os == "Linux"
rv <- paste(strsplit(as.character(getRversion()), "\\.")[[1]][1:2],
    collapse = ".")

# newest versions:
new_pkgs <- do.call(
    rbind,
    lapply(list.files("library", full.names = TRUE),
        function(f) {
            desc <- read.dcf(file.path(f, "DESCRIPTION"))
            desc[, c("Package", "Version")]
        }
    )
)

if (os == "macOS") {
    new_pkgs <- new_pkgs[!new_pkgs[, 1] %in% c("iNZight", "iNZightModules", "vit", "iNZightUpdate", "RGtk2"), ]
    new_pkgs <- new_pkgs[!grepl("^dem", new_pkgs[, 1]), ]
    new_pkgs <- new_pkgs[!grepl("^gWidgets", new_pkgs[, 1]), ]
}

# current versions:
dir <- ifelse(sources,
    "src/contrib",
    sprintf("bin/%s/contrib/%s",
        ifelse(os == "Windows", "windows", "macosx"),
        rv
    )
)

if (!file.exists(file.path(dir, "PACKAGES"))) {
    dir.create(dir, showWarnings = FALSE, recursive = TRUE)
    current_pkgs <- new_pkgs
    current_pkgs[, "Version"] <- rep("0.0.0.1", nrow(current_pkgs))
    NEW <- TRUE
} else {
    current_pkgs <- read.dcf(file.path(dir, "PACKAGES"))
    current_pkgs <- current_pkgs[, c("Package", "Version")]
}

# compare
pkgs <- merge(current_pkgs, new_pkgs,
    by = "Package",
    suffix = c("_cur", "_new"),
    all.y = TRUE
)
pkgs[, "Version_cur"] <-
    ifelse(
        is.na(pkgs[, "Version_cur"]),
        rep("0.0.0.1", nrow(pkgs)),
        pkgs[, "Version_cur"]
    )
pkgs$replace <- numeric_version(pkgs$Version_new) > numeric_version(pkgs$Version_cur)

if (any(pkgs$replace)) {
    # the packages that need updating are:
    replace_pkgs <- as.character(pkgs$Package[pkgs$replace])

    message(" === Building sources ===")
    for (pkg in replace_pkgs)
        x <- system(
            sprintf("R CMD build --no-build-vignettes %s",
                file.path("library", pkg)
            )
        )
        # `x` is a return code (0 = ok; 1 = fail)
        if (x) stop("Failure")

    if (sources) {
        # Delete old sources
        unlink(paste0(file.path(dir, replace_pkgs), "_*.tar.gz"))

        # Move new soures into place
        system(sprintf("mv *.tar.gz %s", dir))
        tools::write_PACKAGES(dir)
    } else {
        message(" === Building binaries ===")
        pkgs <- list.files(pattern = "*.tar.gz")

        for (pkg in pkgs) {
            pkgn <- gsub("_.+\\.tar\\.gz", "", pkg)
            if (os == "Windows") {
                zip <- gsub(".tar.gz", ".zip", pkg, fixed = TRUE)
                x <- system(sprintf("R CMD INSTALL --no-multiarch -l . %s", pkg))
                if (x) stop("Failure")
                zip(zip, pkgn)
            } else {
                tgz <- gsub(".tar.gz", ".tgz", pkg, fixed = TRUE)
                x <- system(sprintf("R CMD INSTALL -l . %s", pkg))
                if (x) stop("Failure")
                system(sprintf("tar czf %s %s", tgz, pkgn))
            }
        }

        # Delete old binaries
        unlink(paste0(file.path(dir, replace_pkgs),
            ifelse(os == "Windows", "_*.zip", "_*.tgz")))

        # Move new binaries into place
        system(sprintf("mv *.%s %s", ifelse(os == "Windows", "zip", "tgz"), dir))
        tools::write_PACKAGES(dir, verbose = TRUE,
            type = ifelse(os == "Windows", "win.binary", "mac.binary")
        )
    }
}

tools::write_PACKAGES(dir, verbose = TRUE)
