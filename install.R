pkgs <- c(
    "RGtk2",
    "cairoDevice",
    "surveyspec",
    "estimability",
    "iNZightTools",
    "iNZightMR",
    "iNZightTS",
    "iNZightTSLegacy",
    "iNZightPlots",
    "iNZightRegression",
    # "iNZightMaps",
    "FutureLearnData",
    "iNZight",
    "iNZightModules",
    "iNZightMultivariate",
    "vit"
    # "demdata",
    # "dembase",
    # "demest",
    # "demlife"
)

OS <- Sys.getenv("OS_TYPE")
if (OS == "Windows") {
    if (!requireNamespace("utf8", quietly = TRUE)) {
        install.packages("utf8", repos = "https://cran.rstudio.com")
    }
    dempkgs <- pkgs[grepl("^dem", pkgs)]
    pkgs <- pkgs[!grepl("^dem", pkgs)]
    pkgs <- pkgs[!pkgs %in% c("RGtk2", "cairoDevice")]
}
if (OS == "macOS") {
    pkgs <- pkgs[!pkgs %in% c("iNZight", "iNZightModules", "vit", "iNZightUpdate", "RGtk2", "cairoDevice")]
    pkgs <- pkgs[!grepl("^dem", pkgs)]
}

options(
    repos = c(
        "https://r.docker.stat.auckland.ac.nz",
        "https://cran.rstudio.com"
    ),
    install.packages.compile.from.source = "never"
)
# install.packages("remotes")

# source_pkgs <- c("scales", "Matrix", "htmltools", "rlang", "bslib", "xfun")
# if (OS == "Windows") {
#     # install.packages("https://cran.r-project.org/src/contrib/Archive/estimability/estimability_1.4.1.tar.gz", repos = NULL, type = "source")
#     install.packages(source_pkgs, type = "source")
# }

message("GTK_PATH: ", Sys.getenv("GTK_PATH"))
message("PATH: ", Sys.getenv("PATH"))

print(list.files(file.path("library")))
print(list.files(.libPaths()[1]))

install.packages("pak", type = "source")
pak::pak(paste0("local::", file.path("library", pkgs)))

# for (pkg in pkgs) {
#     remotes::install_local(
#         file.path("library", pkg),
#         INSTALL_opts = "--no-multiarch"
#     )
# }
if (OS == "Windows") {
    ap <- utils::available.packages()

    # if (getRversion() < package_version("4.2")) {
    #     dem_ap <- dempkgs %in% row.names(ap)
    #     if (any(dem_ap)) {
    #         # install available packages from repo
    #         utils::install.packages(dempkgs[dem_ap])
    #     }
    #     if (any(!dem_ap)) {
    #         # install unavailable packages from local
    #         remotes::install_local(
    #             file.path("library", dempkgs[!dem_ap]),
    #             INSTALL_opts = "--no-multiarch"
    #         )
    #     }
    # }
}
