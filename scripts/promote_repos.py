#!/usr/bin/env python3
"""Merge channel tmp contrib dirs into full bin trees and regenerate index.html."""

from __future__ import annotations

import argparse
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


def list_all_channels() -> list[str]:
    return sorted(
        p.stem
        for p in (ROOT / "channels").glob("*.deps")
        if not p.name.startswith("_")
    )


def resolve_channels() -> list[str]:
    raw = os.environ.get("INPUT_CHANNELS", "").strip()
    if raw:
        return [c.strip() for c in raw.split(",") if c.strip()]
    env_json = os.environ.get("CHANNELS_JSON", "").strip()
    if env_json:
        return json.loads(env_json)
    return list_all_channels()


def pull_channel_bin(ch: str) -> None:
    bin_dir = PROMOTE / ch / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    print(f"Pull s3://{BUCKET}/{ch}/bin -> {bin_dir}")
    aws("s3", "sync", f"s3://{BUCKET}/{ch}/bin", str(bin_dir), check=False)


def pull_flat_bin() -> None:
    flat_bin = PROMOTE / "flat" / "bin"
    flat_bin.mkdir(parents=True, exist_ok=True)
    print(f"Pull s3://{BUCKET}/bin -> {flat_bin}")
    aws("s3", "sync", f"s3://{BUCKET}/bin", str(flat_bin), check=False)


def merge_channel(ch: str) -> None:
    deps = yaml.safe_load((ROOT / "channels" / f"{ch}.deps").read_text(encoding="utf-8"))
    r_minor = deps["r_version"]
    bin_dir = PROMOTE / ch / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)

    pull_channel_bin(ch)

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
    pull_flat_bin()
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
        print(f"Write index.html under {base / 'bin'}")
        subprocess.run(
            [sys.executable, str(script), "--path", "bin"],
            cwd=base,
            check=True,
        )


def has_packages_tree(bin_dir: Path) -> bool:
    contrib = bin_dir / "windows" / "contrib"
    return contrib.is_dir() and any(contrib.rglob("PACKAGES"))


def has_any_content(bin_dir: Path) -> bool:
    return bin_dir.is_dir() and any(bin_dir.rglob("*"))


def push_to_s3(channels: list[str], *, delete: bool) -> None:
    delete_args = ["--delete"] if delete else []

    for ch in channels:
        bin_dir = PROMOTE / ch / "bin"
        if delete and not has_packages_tree(bin_dir):
            print(f"Skip S3 push for {ch}: no PACKAGES under bin/windows/contrib", file=sys.stderr)
            continue
        if not delete and not has_any_content(bin_dir):
            print(f"Skip S3 push for {ch}: empty bin tree", file=sys.stderr)
            continue
        print(f"Push {bin_dir} -> s3://{BUCKET}/{ch}/bin {'(delete)' if delete else '(indexes only)'}")
        aws("s3", "sync", *delete_args, str(bin_dir), f"s3://{BUCKET}/{ch}/bin")

    flat_bin = PROMOTE / "flat" / "bin"
    if flat_bin.is_dir() and has_any_content(flat_bin):
        if delete and not has_packages_tree(flat_bin):
            print("Skip flat bin push: no PACKAGES tree", file=sys.stderr)
        else:
            print(f"Push {flat_bin} -> s3://{BUCKET}/bin {'(delete)' if delete else '(indexes only)'}")
            aws("s3", "sync", *delete_args, str(flat_bin), f"s3://{BUCKET}/bin")


def reindex_only(channels: list[str]) -> int:
    if not channels:
        channels = list_all_channels()
    if not channels:
        print("No channels to reindex", file=sys.stderr)
        return 1

    if PROMOTE.exists():
        shutil.rmtree(PROMOTE)
    PROMOTE.mkdir()

    for ch in channels:
        print(f"=== pull {ch} ===")
        pull_channel_bin(ch)

    print("=== pull flat /bin (legacy root) ===")
    pull_flat_bin()

    print("=== write index.html ===")
    write_indexes()

    print("=== push indexes to S3 (no --delete) ===")
    push_to_s3(channels, delete=False)
    return 0


def promote(channels: list[str]) -> int:
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
    push_to_s3(channels, delete=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reindex-only",
        action="store_true",
        help="Pull published bin trees from S3, regenerate index.html, push without --delete",
    )
    args = parser.parse_args()

    channels = resolve_channels()
    if args.reindex_only:
        return reindex_only(channels)
    return promote(channels)


if __name__ == "__main__":
    sys.exit(main())
