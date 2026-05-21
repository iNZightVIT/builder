#!/usr/bin/env bash
# Initialize submodules required for build-channel-repo (RGtk2, cairoDevice, gWidgets stack).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Rewrite SSH submodule URLs without touching global git config (CI-safe).
git_cfg=(
  -c "url.https://github.com/.insteadOf=git@github.com:"
  -c core.longpaths=true
  -c core.symlinks=false
)

paths=(
  src/RGtk2
  library/cairoDevice
  library/gWidgets
  library/gWidgetsRGtk2
  library/gWidgets2
  library/gWidgets2RGtk2
)

git "${git_cfg[@]}" submodule sync --recursive "${paths[@]}"
git "${git_cfg[@]}" submodule update --init --recursive "${paths[@]}"

for pkg in gWidgets gWidgetsRGtk2 gWidgets2 gWidgets2RGtk2; do
  desc="library/${pkg}/DESCRIPTION"
  if [[ ! -f "${desc}" ]]; then
    echo "ERROR: submodule not checked out: ${desc}" >&2
    exit 1
  fi
  echo "OK ${desc}"
done

# Same check R uses on Windows runners (bash [[ -f ]] can disagree with file.exists()).
Rscript -e '
pkgs <- c("gWidgets", "gWidgetsRGtk2", "gWidgets2", "gWidgets2RGtk2")
missing <- pkgs[!file.exists(file.path("library", pkgs, "DESCRIPTION"))]
if (length(missing)) {
  stop("R cannot see library submodule(s): ", paste(missing, collapse = ", "),
    "\nwd: ", getwd(), call. = FALSE)
}
cat("R OK library submodules\n")
'
