# clean old packages
ca <- commandArgs(TRUE)

pkgs <- list.files("library")
src <- list.files(ca[1])
del <- src[!src %in% pkgs]

for (pkg in del) unlink(file.path(ca, pkg))
