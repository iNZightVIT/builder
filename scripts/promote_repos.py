#!/usr/bin/env python3
"""Merge channel tmp contrib dirs into full bin trees and regenerate index.html."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
BUCKET = os.environ.get("INZIGHT_S3_BUCKET", "r.docker.stat.auckland.ac.nz")
AWS_PROFILE = os.environ.get("AWS_PROFILE", "saml")
PROMOTE = ROOT / "promote"


def aws(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    cmd = ["aws", "--profile", AWS_PROFILE, *args]
    return subprocess.run(cmd, check=check, text=True, capture_output=not check)


def merge_channel(ch: str) -> None:
    deps = yaml.safe_load((ROOT / "channels" / f"{ch}.deps").read_text(encoding="utf-8"))
    r_minor = deps["r_version"]
    bin_dir = PROMOTE / ch / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    # Keep existing published packages and indexes.
    aws("s3", "sync", f"s3://{BUCKET}/{ch}/bin", str(bin_dir), check=False)

    tmp_s3 = f"s3://{BUCKET}/{ch}/bin/windows/contrib/tmp{r_minor}"
    tmp_local = bin_dir / "windows" / "contrib" / f"tmp{r_minor}"
    tmp_local.parent.mkdir(parents=True, exist_ok=True)
    aws("s3", "sync", tmp_s3, str(tmp_local), check=False)

    if tmp_local.is_dir() and any(tmp_local.iterdir()):
        final = bin_dir / "windows" / "contrib" / r_minor
        final.mkdir(parents=True, exist_ok=True)
        subprocess.run(["rsync", "-a", f"{tmp_local}/", f"{final}/"], check=True)
    shutil.rmtree(tmp_local, ignore_errors=True)


def mirror_stable_flat(channels: list[str]) -> None:
    if "stable" not in channels:
        return
    flat_bin = PROMOTE / "flat" / "bin"
    flat_bin.mkdir(parents=True, exist_ok=True)
    aws("s3", "sync", f"s3://{BUCKET}/bin", str(flat_bin), check=False)
    stable_bin = PROMOTE / "stable" / "bin"
    if stable_bin.is_dir():
        subprocess.run(["rsync", "-a", f"{stable_bin}/", f"{flat_bin}/"], check=True)


def write_indexes() -> None:
    script = ROOT / "create_webpages.py"
    targets: list[Path] = []
    if (PROMOTE / "flat" / "bin").is_dir():
        targets.append(PROMOTE / "flat")
    for ch_dir in sorted(PROMOTE.iterdir()):
        if ch_dir.name == "flat":
            continue
        if (ch_dir / "bin").is_dir():
            targets.append(ch_dir)

    for base in targets:
        subprocess.run(
            [sys.executable, str(script), "--path", "bin"],
            cwd=base,
            check=True,
        )


def has_packages_tree(bin_dir: Path) -> bool:
    contrib = bin_dir / "windows" / "contrib"
    return contrib.is_dir() and any(contrib.rglob("PACKAGES"))


def push_to_s3(channels: list[str]) -> None:
    for ch in channels:
        bin_dir = PROMOTE / ch / "bin"
        if has_packages_tree(bin_dir):
            aws("s3", "sync", "--delete", str(bin_dir), f"s3://{BUCKET}/{ch}/bin")
        else:
            print(f"Skip S3 push for {ch}: no PACKAGES under bin/windows/contrib", file=sys.stderr)

    flat_bin = PROMOTE / "flat" / "bin"
    if has_packages_tree(flat_bin):
        aws("s3", "sync", "--delete", str(flat_bin), f"s3://{BUCKET}/bin")
    elif "stable" in channels:
        print("Skip flat bin push: no PACKAGES tree", file=sys.stderr)


def main() -> int:
    channels = json.loads(os.environ.get("CHANNELS_JSON", "[]"))
    if not channels:
        print("No channels to promote", file=sys.stderr)
        return 1

    PROMOTE.mkdir(exist_ok=True)
    for ch in channels:
        print(f"=== promote {ch} ===")
        merge_channel(ch)

    mirror_stable_flat(channels)
    print("=== write index.html ===")
    write_indexes()
    print("=== push to S3 ===")
    push_to_s3(channels)
    return 0


if __name__ == "__main__":
    sys.exit(main())
