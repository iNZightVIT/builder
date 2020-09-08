# build packages

PACKAGE_ORDER <- c(
    "iNZightTools",
    "iNZightMR",
    "iNZightTS",
    "iNZightPlots",
    "iNZightRegression",
    "iNZightMaps",
    "iNZight",
    "iNZightModules"
)

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

if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
    current_pkgs <- new_pkgs
    current_pkgs[, "Version"] <- "0"
    NEW <- TRUE
} else {
    current_pkgs <- read.dcf(file.path(dir, "PACKAGES"))
    current_pkgs <- current_pkgs[, c("Package", "Version")]
}

# compare
pkgs <- merge(current_pkgs, new_pkgs,
    by = "Package",
    suffix = c("_cur", "_new")
)
pkgs$replace <- numeric_version(pkgs$Version_new) > numeric_version(pkgs$Version_cur)

if (any(pkgs$replace)) {
    # the packages that need updating are:
    replace_pkgs <- as.character(pkgs$Package[pkgs$replace])

    message(" === Building sources ===")
    for (pkg in replace_pkgs)
        system(
            sprintf("R CMD build --no-build-vignettes %s",
                file.path("library", pkg)
            )
        )

    if (sources) {
        # Delete old sources
        unlink(paste0(file.path(dir, replace_pkgs), "*"))

        # Move new soures into place
        system(sprintf("mv *.tar.gz %s", dir))
        tools::write_PACKAGES(dir)
    } else {
        message(" === Building binaries ===")
        pkgs <- list.files(pattern = "*.tar.gz")

        # but they need the correct order ...
        f <- sapply(PACKAGE_ORDER, function(x) pkgs[which(grepl(paste0(x, "_"), pkgs))])
        pkgs <- as.character(unlist(f))

        options(
            repos = c("https://cran.rstudio.com",
                "https://r.docker.stat.auckland.ac.nz")
        )
        install.packages("remotes")
        for (pkg in PACKAGE_ORDER) {
            remotes::install_local(file.path("library", pkg))
        }

        for (pkg in pkgs) {
            zip <- gsub(".tar.gz", ".zip", pkg, fixed = TRUE)
            pkgn <- gsub("_*.tar.gz", "", pkg, fixed = TRUE)

            system(sprintf("R CMD INSTALL -l . %s", pkg))
            zip(zip, pkgn)
        }

        # Delete old binaries
        unlink(paste0(file.path(dir, replace_pkgs), "*"))

        # Move new binaries into place
        system(sprintf("mv *.zip %s", dir))
        tools::write_PACKAGES(dir)
    }
}
