# build nightly instance of iNZight

options(
    repos = c(
        "https://r.docker.stat.auckland.ac.nz", # for some packages like gWidgets, etc ...
        "https://cran.rstudio.com"
    ),
    install.packages.compile.from.source = "never"
)

pkgs <- c(
    "iNZightTools",
    "iNZightMR",
    "iNZightTS",
    "iNZightPlots",
    "iNZightRegression",
    "iNZightMaps",
    "FutureLearnData",
    "iNZight",
    "iNZightModules",
    "iNZightMultivariate",
    # "ggsfextra",
    "vit"
)

curr <- as.character(installed.packages()[, "Package"])

# download all
sapply(pkgs, function(pkg) {
    utils::download.file(
        sprintf("https://github.com/iNZightVIT/%s/archive/dev.zip", pkg),
        sprintf("%s.zip", pkg),
        quiet = TRUE
    )
})

# query and install dependencies
deps <- sapply(pkgs, function(pkg) {
    d <- sprintf("%s-dev", pkg)
    on.exit(unlink(d, recursive = TRUE, force = TRUE))
    desc <- utils::unzip(
        sprintf("%s.zip", pkg),
        files = sprintf("%s/DESCRIPTION", d)
    )
    desc <- read.dcf(desc)
    fields <- c("Imports", "Depends", "Suggests")
    deps <- desc[, fields[fields %in% colnames(desc)]]
    deps <- sapply(deps, strsplit, split = ",\n", fixed = TRUE)
    deps <- as.character(do.call(c, deps))
    deps <- unique(gsub("\ .+", "", deps))
    deps[!deps %in% pkgs]
})
deps <- unique(do.call(c, deps))
deps <- deps[!deps %in% curr] # don't try installing recommend packages (i.e., come with R)
install.packages(deps)

# install iNZight packages
sapply(pkgs, function(pkg) {
    d <- sprintf("%s-dev", pkg)
    on.exit(unlink(d, recursive = TRUE, force = TRUE))
    utils::unzip(sprintf("%s.zip", pkg))
    install.packages(d,
        repos = NULL,
        type = "source",
        INSTALL_opts = "--no-multiarch"
    )
})

# clean up
unlink(paste0(pkgs, ".zip"))

# create directories
# dir.create(file.path(".cache", "R", "iNZight"), recursive = TRUE)
# dir.create(file.path(".config", "R", "iNZight"), recursive = TRUE)
# writeLines("list()\n", file.path(".config", "R", "iNZight", "preferences.R"))
