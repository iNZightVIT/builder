# iNZight Builder

Windows CI for iNZight: per-channel package repositories (win.binary) and full NSIS installers. macOS builds are deprecated.

Published artifacts live at [https://r.docker.stat.auckland.ac.nz](https://r.docker.stat.auckland.ac.nz).

## Channels

Each channel is defined by a committed deps file under `channels/`:

| Channel | Config | Purpose |
|---------|--------|---------|
| **development** | `channels/development.deps` | Moving GitHub branches (develop/main, release bump) |
| **stable** | `channels/stable.deps` | Explicit GitHub refs/tags + CRAN (no `library/` submodules) |
| **pinned** | `channels/inzight-X.Y.deps` | Frozen package set; add when shipping a release |

Channel win.binary repos on S3:

- `/development/bin/windows/contrib/<R minor>/`
- `/stable/bin/windows/contrib/<R minor>/`
- `/inzight-X.Y/bin/windows/contrib/<R minor>/`

After a stable publish, `stable/bin/…` is mirrored to the flat `/bin/…` tree for backward compatibility.

## Workflow

GitHub Actions workflow: [`.github/workflows/build-inzight.yaml`](.github/workflows/build-inzight.yaml)

1. **detect-channels** — hash `*.deps` + shared scripts; on schedule, skip unchanged channels (S3 sidecar `channels/<channel>.last-built`).
2. **build-channel** (matrix) — install GTK/RGtk2 from the published repo, `scripts/install_channel.R`, `scripts/build_binaries.R`, upload repo + full installer.
3. **promote-repos** — promote `tmp*` staging dirs, mirror stable → flat `bin/`, regenerate HTML, invalidate CloudFront.
4. **update-website** — dispatch to `inzight-www`.

Triggers: nightly cron, push to `master` (paths under `channels/`, `scripts/`, installers, workflow), and `workflow_dispatch` (`channels`, `rebuild_all`, `skip_installer`).

Commit message tokens: `skip repo`, `skip installer`.

## RGtk2 / cairoDevice

These are **never** built or uploaded in CI. Binaries are maintained manually on a physical Windows machine:

```bash
Rscript scripts/build_rgtk2_windows_artifacts.R
```

CI installs them from the flat repository via `install_gtk.R` (`INZIGHT_CI=1` disables local zip copy into contrib).

## Local scripts

| Script | Role |
|--------|------|
| `scripts/install_channel.R --channel=<name>` | Install packages for a channel |
| `scripts/build_binaries.R --channel=<name>` | Build missing win.binary zips (denylist: RGtk2, cairoDevice) |
| `scripts/channel_version.R --channel=<name>` | Installer version string |
| `scripts/detect_channels.py` | Channel selection for CI |
| `install_nightly.R` | Wrapper for `--channel=development` |

Legacy `build.R` / `install.R` (library submodules) remain for reference but are not used by the unified workflow.

## Installers (v1)

Each channel produces a **full** installer (R + packages embedded). There is no runtime channel switching in the installer.

| Channel | Example download |
|---------|------------------|
| development | `downloads/iNZightVIT-installer-nightly.exe` |
| stable | `downloads/Windows/iNZightVIT-installer-<version>.exe` |
| pinned | `downloads/<channel>/iNZightVIT-installer-<version>.exe` |
