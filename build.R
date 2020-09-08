# build packages

os <- Sys.getenv("OS_TYPE")

sources <- os == "Linux"

if (sources) {
    print("Building sources")
    system("ls -lR src")
} else {
    print("Building binaries")
}
