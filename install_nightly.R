# build nightly instance of iNZight

options(
    repos = c(
        "https://r.docker.stat.auckland.ac.nz", # for some packages like gWidgets, etc ...
        "https://cran.rstudio.com"
    ),
    install.packages.compile.from.source = "never"
)

pkgs <- c(
    # "RGtk2",
    # "cairoDevice",
    "tmelliott/translatr",
    "tmelliott/surveyspec",
    "iNZightTools",
    "iNZightMR",
    "tidyverts/feasts@v0.4.1",
    "tidyverts/fabletools@v0.5.1",
    "iNZightTS@2.0.3",
    "iNZightTSLegacy",
    "iNZightPlots",
    "iNZightRegression",
    # "iNZightMaps",
    "FutureLearnData",
    "iNZight",
    "iNZightModules",
    "iNZightMultivariate",
    # "ggsfextra",
    "vit"
)

if (!requireNamespace("pak", quietly = TRUE)) {
    install.packages("pak", type = "source")
}
pak::pak(c("httr", "lubridate"))

curr <- as.character(installed.packages()[, "Package"])
print(curr)

# Expand shorthand package specs to owner/repo@ref for pak::pkg_install().
# - Bare names default to iNZightVIT/<pkg>.
# - If @ref is omitted, pick develop, else main, else master (via GitHub API),
#   then optionally prefer a newer matching release* branch.
expand_nightly_github_pkg <- function(pkg) {
    default_org <- "iNZightVIT"
    pkg <- trimws(pkg)
    if (!nzchar(pkg)) {
        return(NA_character_)
    }

    at <- regexpr("@", pkg, fixed = TRUE)[1L]
    if (at > 0L) {
        repo_spec <- substring(pkg, 1L, at - 1L)
        ref <- substring(pkg, at + 1L)
        parts <- strsplit(repo_spec, "/", fixed = TRUE)[[1L]]
        if (length(parts) == 1L) {
            owner <- default_org
            name <- parts[[1L]]
        } else {
            owner <- parts[[1L]]
            name <- paste(parts[-1L], collapse = "/")
        }
        return(sprintf("%s/%s@%s", owner, name, ref))
    }

    parts <- strsplit(pkg, "/", fixed = TRUE)[[1L]]
    if (length(parts) == 1L) {
        owner <- default_org
        name <- parts[[1L]]
    } else {
        owner <- parts[[1L]]
        name <- paste(parts[-1L], collapse = "/")
    }

    url <- sprintf("https://api.github.com/repos/%s/%s/branches", owner, name)
    x <- httr::GET(url)
    branches <- httr::content(x, as = "parsed")
    if (httr::http_error(x) || (is.list(branches) && !is.null(branches$message))) {
        err <- if (is.list(branches) && !is.null(branches$message)) {
            as.character(branches$message)[1L]
        } else {
            paste0("HTTP ", httr::status_code(x))
        }
        warning("Could not list branches for ", owner, "/", name, ": ", err, call. = FALSE)
        return(NA_character_)
    }
    if (!length(branches)) {
        warning("No branches returned for ", owner, "/", name, call. = FALSE)
        return(NA_character_)
    }

    branch_names <- vapply(branches, function(b) {
        n <- b$name
        if (is.null(n) || !nzchar(n)) NA_character_ else as.character(n)[1L]
    }, character(1L))
    names(branches) <- branch_names

    branch <- NULL
    for (cand in c("develop", "main", "master")) {
        if (cand %in% branch_names) {
            branch <- cand
            break
        }
    }
    if (is.null(branch)) {
        ok <- branch_names[!is.na(branch_names) & nzchar(branch_names)]
        if (!length(ok)) {
            warning("No usable branch names for ", owner, "/", name, call. = FALSE)
            return(NA_character_)
        }
        branch <- ok[[1L]]
    }

    release_branches <- branches[grepl("release", branch_names, ignore.case = TRUE)]
    if (length(release_branches)) {
        dev_branch <- branches[[branch]]
        dev_date <- httr::content(httr::GET(dev_branch$commit$url))$commit$author$date |>
            lubridate::ymd_hms()

        release_dates <- lapply(release_branches, function(b) {
            data.frame(
                branch = b$name,
                date =
                    httr::content(httr::GET(b$commit$url))$commit$author$date |>
                        lubridate::ymd_hms()
            )
        })
        release_dates <- do.call(rbind, release_dates)
        release_row <- release_dates[which.max(release_dates$date), , drop = FALSE]
        if (release_row$date > dev_date) {
            branch <- sprintf("refs/heads/%s", release_row$branch)
        }
    }

    sprintf("%s/%s@%s", owner, name, branch)
}

# download all
deps <- sapply(pkgs, expand_nightly_github_pkg)

# pkgs <- gsub(".*/", "", pkgs)

# query and install dependencies
# deps <- sapply(pkgs, function(pkg) {
#     if (!file.exists(sprintf("%s.zip", pkg))) {
#         return()
#     }
#     d <- gsub("/$", "", utils::unzip(sprintf("%s.zip", pkg), list = TRUE)[1, "Name"])
#     on.exit(unlink(d, recursive = TRUE, force = TRUE))
#     desc <- utils::unzip(
#         sprintf("%s.zip", pkg),
#         files = sprintf("%s/DESCRIPTION", d)
#     )
#     desc <- read.dcf(desc)
#     fields <- c("Imports", "Depends", "Suggests")
#     deps <- desc[, fields[fields %in% colnames(desc)]]
#     deps <- sapply(deps, strsplit, split = ",\n", fixed = TRUE)
#     deps <- as.character(do.call(c, deps))
#     deps <- unique(gsub("\ .+", "", deps))
#     deps[!deps %in% pkgs]
# })
# deps <- unique(do.call(c, deps))
# deps <- deps[!deps %in% curr] # don't try installing recommend packages (i.e., come with R)
print(deps)
# # install.packages(deps)
pak::pkg_install(deps)

# install iNZight packages
# sapply(pkgs, function(pkg) {
#     if (!file.exists(sprintf("%s.zip", pkg))) {
#         # install.packages(pkg)
#         pak::pkg_install(pkg)
#         return()
#     }
#     d <- gsub("/$", "", utils::unzip(sprintf("%s.zip", pkg), list = TRUE)[1, "Name"])
#     on.exit(unlink(d, recursive = TRUE, force = TRUE))
#     utils::unzip(sprintf("%s.zip", pkg))
#     install.packages(d,
#         repos = NULL,
#         type = "source",
#         INSTALL_opts = "--no-multiarch"
#     )
# })

# clean up
# unlink(paste0(pkgs, ".zip"))

# create directories
# dir.create(file.path(".cache", "R", "iNZight"), recursive = TRUE)
# dir.create(file.path(".config", "R", "iNZight"), recursive = TRUE)
# writeLines("list()\n", file.path(".config", "R", "iNZight", "preferences.R"))
