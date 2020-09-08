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
pkgs <- read.dcf(file.path(dir, "PACKAGES"))
print(pkgs)

if (sources) {
    message(" === Building sources ===")

} else {
    print("Building binaries")
}
