# Compute the version of iNZight to use
url <- "https://r.docker.stat.auckland.ac.nz/downloads/VERSION"
v <- package_version(readLines(url))
p <- v[[1L, 4L]]
if (is.na(p)) p <- 0
VERSION <- paste(as.character(v[1L, 1:3]), p, sep = ".")

message(VERSION)
# this will be uploaded with the installer (and not if build fails!)
# write.dcf(pkgs, file = file.path("downloads", "windows_versions"))
# writeLines(VERSION, vfile)
cat(VERSION)
