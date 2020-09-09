# Compute the version of iNZight to use
# f <- tempfile()
# verf <- try(
#     download.file(
#         "https://r.docker.stat.auckland.ac.nz/downloads/windows_versions.txt",
#         f
#     ),
# )
# if (inherits(verf, "try-error")) {
#     vers <- NA
# } else {
#     vers <- read.dcf(f)
# }

# pkgs <- c(
#     "iNZightTools",
#     "iNZightMR",
#     "iNZightTS",
#     "iNZightPlots",
#     "iNZightRegression",
#     "iNZightMaps",
#     "FutureLearnData",
#     "iNZight",
#     "iNZightModules",
#     "iNZightMultivariate",
#     "vit"
# )
# new <- sapply(pkgs, function(p) as.character(packageVersion(p)))
# pkgs <- data.frame(package = pkgs, version = new)

cat(as.character(packageVersion("iNZight")))
