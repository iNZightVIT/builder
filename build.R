# build packages

os <- Sys.getenv("OS_TYPE")
sources <- os == "Linux"
rv <- paste(strsplit(as.character(getRversion()), "\\.")[[1]][1:2],
    collapse = ".")

# current versions:
dir <- ifelse(sources,
    "src/contrib",
    sprintf("windows/contrib/%s", rv)
)
current_pkgs <- read.dcf(file.path(dir, "PACKAGES"))
current_pkgs <- current_pkgs[, c("Package", "Version")]

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

# compare
pkgs <- merge(current_pkgs, new_pkgs,
    by = "Package",
    suffix = c("_cur", "_new")
)
pkgs$replace <- numeric_version(pkgs$Version_new) > numeric_version(pkgs$Version_cur)

if (any(pkgs$replace)) {
    # the packages that need updating are:
    replace_pkgs <- as.character(pkgs$Package[pkgs$replace])
    if (sources) {
        message(" === Building sources ===")
        for (pkg in replace_pkgs)
            system(
                sprintf("R CMD build --no-build-vignettes %s",
                    file.path("library", pkg)
                )
            )
        system(sprintf("mv *.tar.gz %s", dir))
        tools::write_PACKAGES(dir)
    } else {
        print("Building binaries")
    }
}

system(sprintf("ls -lR %s", dir))