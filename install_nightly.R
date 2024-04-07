# build nightly instance of iNZight

options(
    repos = c(
        "https://r.docker.stat.auckland.ac.nz", # for some packages like gWidgets, etc ...
        "https://cran.rstudio.com"
    )
    # install.packages.compile.from.source = "never"
)

pkgs <- c(
    # "RGtk2",
    # "cairoDevice",
    "tmelliott/surveyspec",
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

install.packages(c("httr", "lubridate", "knitr"))
install.packages(c("Matrix", "rlang", "tidyselect", "scales", "htmltools", "sass"), type = "source")
install.packages("https://cran.r-project.org/src/contrib/Archive/estimability/estimability_1.4.1.tar.gz", repos = NULL, type = "source")
install.packages("progress", type = "source")

curr <- as.character(installed.packages()[, "Package"])
print(curr)

# download all
sapply(pkgs, function(pkg) {
    branch <- "dev"
    if (grepl("@", pkg)) {
        pkg <- strsplit(pkg, "@")[[1]]
        branch <- sprintf("refs/tags/%s", pkg[2])
        pkg <- pkg[1]
        return()
    }

    pkg <- strsplit(pkg, "/")[[1]]
    if (length(pkg) == 1L) pkg <- c("iNZightVIT", pkg)

    # if there is a release- branch NEWER than the dev branch,
    # use that instead:
    x <- httr::GET(sprintf("https://api.github.com/repos/%s/%s/branches", pkg[1], pkg[2]))
    branches <- httr::content(x)
    if (!is.null(branches$message)) {
        return()
    }

    names(branches) <- sapply(branches, function(z) z$name)
    releaseBranches <- branches[sapply(names(branches), function(z) grepl("release", z))]
    if (branch == "dev" && is.null(branches[[branch]])) {
        if (!is.null(branches$develop)) {
            branch <- "develop"
        } else if (!is.null(branches$main)) {
            branch <- "main"
        } else {
            branch <- "master"
        }
    }
    if (length(releaseBranches)) {
        devBranch <- branches[[branch]]
        devDate <- httr::content(httr::GET(devBranch$commit$url))$commit$author$date |>
            lubridate::ymd_hms()

        releaseDates <- lapply(releaseBranches, function(b) {
            data.frame(
                branch = b$name,
                date =
                    httr::content(httr::GET(b$commit$url))$commit$author$date |>
                        lubridate::ymd_hms()
            )
        })
        releaseDates <- do.call(rbind, releaseDates)
        releaseBranch <- releaseDates[which.max(releaseDates$date), ]
        if (releaseBranch$date > devDate) {
            branch <- sprintf("refs/heads/%s", releaseBranch$branch)
        }
    }

    utils::download.file(
        sprintf("https://github.com/%s/%s/archive/%s.zip", pkg[1], pkg[2], branch),
        sprintf("%s.zip", pkg[2]),
        quiet = TRUE
    )
})

pkgs <- gsub(".*/", "", pkgs)

# query and install dependencies
deps <- sapply(pkgs, function(pkg) {
    if (!file.exists(sprintf("%s.zip", pkg))) {
        return()
    }
    d <- gsub("/$", "", utils::unzip(sprintf("%s.zip", pkg), list = TRUE)[1, "Name"])
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
print(deps)
install.packages(deps)

# install iNZight packages
sapply(pkgs, function(pkg) {
    if (!file.exists(sprintf("%s.zip", pkg))) {
        install.packages(pkg)
        return()
    }
    d <- gsub("/$", "", utils::unzip(sprintf("%s.zip", pkg), list = TRUE)[1, "Name"])
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
