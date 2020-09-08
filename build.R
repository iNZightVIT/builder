# build packages

os <- Sys.getenv("OS_TYPE")

sources <- os == "Linux"

if (sources) {
    print("Building sources")
} else {
    print("Building binaries")
}
