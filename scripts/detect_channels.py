#!/usr/bin/env python3
"""Detect which iNZight channels need building (GitHub Actions detect-channels job)."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
CHANNELS_DIR = ROOT / "channels"
HASH_INPUTS = [
    "channels/_shared.R",
    "R/channel_resolve.R",
    "scripts/install_channel.R",
    "scripts/build_binaries.R",
    "scripts/build_rgtk2_channel.R",
    "scripts/build_rgtk2_windows_artifacts.R",
    "scripts/install_channel_from_repo.R",
    "install_gtk.R",
    "R/rgtk2_cairo_install.R",
    "scripts/promote_repos.py",
]
S3_BUCKET = os.environ.get("INZIGHT_S3_BUCKET", "r.docker.stat.auckland.ac.nz")
AWS_PROFILE = os.environ.get("AWS_PROFILE", "saml")


def list_channels() -> list[str]:
    return sorted(
        p.stem
        for p in CHANNELS_DIR.glob("*.deps")
        if not p.name.startswith("_")
    )


def channel_hash(channel: str) -> str:
    parts: list[str] = []
    deps = CHANNELS_DIR / f"{channel}.deps"
    if not deps.is_file():
        raise FileNotFoundError(deps)
    parts.append(deps.read_text(encoding="utf-8"))
    for rel in HASH_INPUTS:
        path = ROOT / rel
        if not path.is_file():
            raise FileNotFoundError(path)
        parts.append(path.read_text(encoding="utf-8"))
    blob = "\n".join(parts).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def s3_last_built(channel: str) -> str | None:
    key = f"s3://{S3_BUCKET}/channels/{channel}.last-built"
    try:
        out = subprocess.run(
            ["aws", "--profile", AWS_PROFILE, "s3", "cp", key, "-"],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if out.returncode != 0:
        return None
    return out.stdout.strip() or None


def write_s3_last_built(channel: str, digest: str) -> None:
    key = f"s3://{S3_BUCKET}/channels/{channel}.last-built"
    subprocess.run(
        ["aws", "--profile", AWS_PROFILE, "s3", "cp", "-", key],
        input=digest,
        text=True,
        check=True,
    )


def channels_from_dispatch() -> tuple[list[str] | None, bool]:
    channels_raw = os.environ.get("INPUT_CHANNELS", "").strip()
    rebuild_all = os.environ.get("INPUT_REBUILD_ALL", "").lower() in ("1", "true", "yes")
    if channels_raw:
        return [c.strip() for c in channels_raw.split(",") if c.strip()], rebuild_all
    return None, rebuild_all


def channels_from_push() -> set[str]:
    before = os.environ.get("GITHUB_EVENT_BEFORE", "")
    if not before or before == "0000000000000000000000000000000000000000":
        return set(list_channels())
    try:
        out = subprocess.run(
            ["git", "diff", "--name-only", before, "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            cwd=ROOT,
        )
    except subprocess.CalledProcessError:
        return set(list_channels())
    changed = {line.strip() for line in out.stdout.splitlines() if line.strip()}
    selected: set[str] = set()
    global_change = False
    for path in changed:
        if path.startswith("channels/") and path.endswith(".deps"):
            selected.add(Path(path).stem)
        elif path in HASH_INPUTS or path == ".github/workflows/build-inzight.yaml":
            global_change = True
        elif path.startswith("installers/"):
            global_change = True
    if global_change:
        return set(list_channels())
    return selected


def main() -> int:
    event = os.environ.get("GITHUB_EVENT_NAME", "workflow_dispatch")
    all_channels = list_channels()
    if not all_channels:
        print("No channels/*.deps files found", file=sys.stderr)
        return 1

    dispatch_channels, rebuild_all = channels_from_dispatch()
    skip_repo = "skip repo" in os.environ.get("GITHUB_EVENT_HEAD_COMMIT_MESSAGE", "").lower()

    to_build: list[str] = []
    for channel in all_channels:
        if dispatch_channels is not None and channel not in dispatch_channels:
            continue
        digest = channel_hash(channel)
        if skip_repo and event != "workflow_dispatch":
            continue
        if rebuild_all:
            to_build.append(channel)
            continue
        if event == "schedule":
            if digest != s3_last_built(channel):
                to_build.append(channel)
        elif event == "push":
            push_set = channels_from_push()
            if channel in push_set:
                to_build.append(channel)
        else:
            # workflow_dispatch without channel filter
            if dispatch_channels is None or channel in dispatch_channels:
                to_build.append(channel)

    # Deduplicate preserving order
    seen: set[str] = set()
    ordered: list[str] = []
    for ch in to_build:
        if ch not in seen:
            seen.add(ch)
            ordered.append(ch)

    payload = {"channel": ordered}
    print(json.dumps(payload))

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as fh:
            fh.write(f"channels={json.dumps(ordered)}\n")
            fh.write(f"has_channels={'true' if ordered else 'false'}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
