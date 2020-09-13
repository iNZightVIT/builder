f <- file.path("website", "iNZight", "assets", "objects", "setup.php")
s <- readLines(f)
lv <- grep("$inzight_version", s, fixed = TRUE)
ld <- grep("$release_date", s, fixed = TRUE)

DESC <- read.dcf("library/iNZight/DESCRIPTION")

s[lv] <- sprintf(gsub("\".+\"", "\"%s\"", s[lv]), DESC[,"Version"])
s[ld] <- sprintf(gsub("\".+\"", "\"%s\"", s[ld]),
    format(as.Date(DESC[,"Date"]), "%e %B %Y")
)

writeLines(s, f)

cat(DESC[,"Version"][[1]])
