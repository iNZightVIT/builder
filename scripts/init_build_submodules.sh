#!/usr/bin/env bash
# Initialize submodules required for build-channel-repo (RGtk2, cairoDevice, gWidgets stack).
set -euo pipefail

git config --global url."https://github.com/".insteadOf "git@github.com:"

paths=(
  src/RGtk2
  library/cairoDevice
  library/gWidgets
  library/gWidgetsRGtk2
  library/gWidgets2
  library/gWidgets2RGtk2
)

git submodule sync --recursive "${paths[@]}"
git submodule update --init --depth 1 --recursive "${paths[@]}"

for pkg in gWidgets gWidgetsRGtk2 gWidgets2 gWidgets2RGtk2; do
  desc="library/${pkg}/DESCRIPTION"
  if [[ ! -f "${desc}" ]]; then
    echo "ERROR: submodule not checked out: ${desc}" >&2
    exit 1
  fi
  echo "OK ${desc}"
done
