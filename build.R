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

# current versions:
dir <- ifelse(sources,
    "src/contrib",
    sprintf("bin/windows/contrib/%s", rv)
)

if (!file.exists(file.path(dir, "PACKAGES"))) {
    dir.create(dir, recursive = TRUE)
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
        unlink(paste0(file.path(dir, replace_pkgs), "*"))

        # Move new soures into place
        system(sprintf("mv *.tar.gz %s", dir))
        tools::write_PACKAGES(dir)
    } else {
        message(" === Building binaries ===")
        pkgs <- list.files(pattern = "*.tar.gz")

        for (pkg in pkgs) {
            zip <- gsub(".tar.gz", ".zip", pkg, fixed = TRUE)
            pkgn <- gsub("_.+\\.tar\\.gz", "", pkg)

            x <- system(sprintf("R CMD INSTALL --no-multiarch -l . %s", pkg))
            if (x) stop("Failure")
            zip(zip, pkgn)
        }

        # Delete old binaries
        unlink(paste0(file.path(dir, replace_pkgs), "*"))

        # Move new binaries into place
        system(sprintf("mv *.zip %s", dir))
        tools::write_PACKAGES(dir, verbose = TRUE)
    }
}
