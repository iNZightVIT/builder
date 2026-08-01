#!/usr/bin/env bash
# Initialize submodules required for build-channel-repo (RGtk2, cairoDevice, gWidgets stack).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Rewrite SSH submodule URLs without relying on global git config alone.
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

git "${git_cfg[@]}" submodule sync -- "${paths[@]}"
git "${git_cfg[@]}" submodule update --init --force -- "${paths[@]}"

for pkg in gWidgets gWidgetsRGtk2 gWidgets2 gWidgets2RGtk2; do
  desc="library/${pkg}/DESCRIPTION"
  if [[ ! -f "${desc}" ]]; then
    echo "ERROR: submodule not checked out: ${desc}" >&2
    ls -la "library/${pkg}" >&2 || true
    git submodule status "library/${pkg}" >&2 || true
    exit 1
  fi
  echo "OK ${desc}"
done

# Bash [[ -f ]] and R file.exists() can disagree on Windows runners.
if command -v Rscript >/dev/null 2>&1; then
  Rscript "${repo_root}/scripts/verify_library_submodules.R"
fi
