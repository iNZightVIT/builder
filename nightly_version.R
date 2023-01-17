v <- strsplit(as.character(packageVersion("iNZight")), "\\.")[[1]]
if (length(v) < 3L) {
    v <- c(v, rep("0", 3L - length(v)))
} else if (length(v) == 3L) {
    v[4] <- format(Sys.time(), "%Y%m%d", tz = "Pacific/Auckland")
} else if (length(v) == 4L) {
    v[4] <- ifelse(v[4] == "9000",
        format(Sys.time(), "%Y%m%d", tz = "Pacific/Auckland"),
        v[4]
    )
} else {
    stop("Invalid version number")
}
cat(paste(v, collapse = "."))
