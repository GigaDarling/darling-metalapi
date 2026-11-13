#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Integrate this source release into its pinned Darling checkout."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--darling", required=True, type=Path)
    parser.add_argument("--check", action="store_true", help="validate without changing files")
    args = parser.parse_args()
    darling = args.darling.resolve()
    manifest = json.loads((ROOT / "upstream.json").read_text())
    repositories = {"darling": darling, "metal": darling / "src/external/metal",
                    "cocotron": darling / "src/external/cocotron",
                    "darlingserver": darling / "src/external/darlingserver",
                    "indium": darling / "src/external/metal/deps/indium",
                    "mslc": ROOT / "deps/mslc"}
    for name, path in repositories.items():
        revision = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
        if revision != manifest[name]["revision"]:
            parser.error(f"{name}: expected {manifest[name]['revision']}, got {revision}")
    for name in ("metal", "cocotron", "darlingserver", "indium"):
        status = subprocess.check_output(["git", "-C", str(repositories[name]),
                                          "status", "--porcelain", "--untracked-files=normal"], text=True)
        if status:
            parser.error(f"{name}: use a clean checkout; local changes would be overwritten")
    if (darling / "tools/metal-baseline").exists():
        parser.error("tools/metal-baseline already exists; use a clean checkout")
    compiler = ROOT / "deps/mslc/sources.cmake"
    if not compiler.is_file():
        parser.error("initialize this repository's submodules first: git submodule update --init --recursive")
    patches = [(darling, "darling-tools.patch"),
               (repositories["cocotron"], "cocotron-layer-init.patch"),
               (repositories["darlingserver"], "darlingserver-openssl4.patch"),
               (repositories["indium"], "indium-viewport.patch")]
    # Check every patch before making the first change.
    for path, patch in patches:
        subprocess.run(["git", "-C", str(path), "apply", "--check", str(ROOT / "patches" / patch)], check=True)
    if args.check:
        print("PASS pinned revisions, clean integration targets and all patches")
        return
    shutil.copytree(ROOT / "metal", repositories["metal"], dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".git", "deps", ".gitmodules"))
    shutil.copytree(ROOT / "demo", darling / "tools/metal-baseline")
    for path, patch in patches:
        subprocess.run(["git", "-C", str(path), "apply", str(ROOT / "patches" / patch)], check=True)
    print("Integrated Metal API sources, demo and compatibility patches into", darling)


if __name__ == "__main__":
    main()
