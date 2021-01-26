v <- strsplit(as.character(packageVersion("iNZight")), "\\.")[[1]]
if (v[4] == 9000) {
    v[4] <- format(Sys.time(), "%Y%m%d")
}
cat(paste(v, collapse = "."))
