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
    "ggsfextra",
    "vit"
)

if (OS == "Windows" && !requireNamespace('utf8', quietly = TRUE)) {
    install.packages("utf8", repos = "https://cran.rstudio.com")
}

if (!requireNamespace("utf8", TRUE)) install.packages("utf8")
options(
    repos = c(
        "https://r.docker.stat.auckland.ac.nz",
        "https://cran.rstudio.com"
    ),
    install.packages.compile.from.source = "never"
)
install.packages("remotes")
for (pkg in pkgs) {
    remotes::install_local(
        file.path("library", pkg),
        INSTALL_opts = "--no-multiarch"
    )
}
