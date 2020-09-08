rv <- paste(strsplit(as.character(getRversion()), "\\.")[[1]][1:2],
    collapse = ".")
cat(rv)
