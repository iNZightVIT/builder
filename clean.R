# clean old packages
ca <- commandArgs(TRUE)

pkgs <- list.files("library")
src <- gsub("_.+", "", list.files(ca[1], ".tar.gz"))
del <- src[!src %in% pkgs]

for (pkg in del)
    unlink(paste0(file.path(ca, pkg), "*.tar.gz"))
