# iNZight Builder

This repository exists for developers to easily release iNZight packages (as an alternative to CRAN) and deploy updates without requiring a dedicated machine.


## How it works

The main repository is at https://r.docker.stat.auckland.ac.nz, and has source and binaries for packages for R-release, R-devel, and R-oldrel on Windows, and (currently not) macOS.

1. Github Actions pulls this repository and the master version of all packages
2. installs R
3. syncs (pull) repository (including datestamps)
4. builds source/binary for any packages which are newer than the repo
5. creates `PACKAGES` file
6. syncs (push) repository

Next, the windows installer is built and uploaded.
