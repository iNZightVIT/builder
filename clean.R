# clean old packages
ca <- commandArgs(TRUE)
dir <- ca[1]
ext <- ca[2]

pkgs <- list.files("library")
src <- gsub("_.+", "", list.files(dir, ext))
del <- src[!src %in% pkgs]

for (pkg in del)
    unlink(paste0(file.path(dir, pkg), "_*", ext))
