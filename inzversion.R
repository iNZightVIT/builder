# Compute the version of iNZight to use
f <- "downloads/windows_versions"
if (file.exists(f)) {
    vers <- read.dcf(f)
} else {
    vers <- NA
}

pkgs <- c(
    "iNZightTools",
    "iNZightMR",
    "iNZightTS",
    "iNZightPlots",
    "iNZightRegression",
    "FutureLearnData",
    "iNZight",
    "iNZightModules",
    "vit",
    "iNZightUpdate"
)

new <- sapply(pkgs, function(p) as.character(packageVersion(p)))

pkgs <- data.frame(package = pkgs, version = new)

if (length(vers) == 1L && is.na(vers)) {
    # nothing to compare to
    VERSION <- pkgs[pkgs$package == "iNZight", "version"]
} else {
    # compare versions:
    comp <- merge(pkgs, vers,
        by = "package",
        suffixes = c(".new", ".cur"),
        all.x = TRUE
    )
    # any NA go to zero
    comp$version.new <- ifelse(is.na(comp$version.new), "0.0.1", comp$version.new)
    comp$version.cur <- ifelse(is.na(comp$version.cur), "0.0.1", comp$version.cur)
    comp$update <-
        package_version(comp$version.cur) < package_version(comp$version.new)
    if (any(is.na(comp$update)) || any(comp$update)) {
        # updates are required
        VERSION <- pkgs[pkgs$package == "iNZight", "version"]
        if (!comp[comp$package == "iNZight", "update"]) {
            # need to add 1 to patch version since iNZight package not updated
            # (but others are):
            v <- package_version(VERSION)
            p <- v[[1L, 4L]]
            if (is.na(p)) p <- 0
            VERSION <- paste(as.character(v[1L, 1:3]), p + 1, sep = "-")
        }
    } else {
        # no update necessary
        message("No changes - skipping installer build.")
        quit(status = 1)
    }
}
message(VERSION)
# this will be uploaded with the installer (and not if build fails!)
write.dcf(pkgs, file = file.path("downloads", "windows_versions"))

cat(VERSION)
