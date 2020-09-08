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
    "vit"
)

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
    remotes::install_deps(
        dependencies = TRUE,
        INSTALL_opts = "--no-multiarch"
    )
}
