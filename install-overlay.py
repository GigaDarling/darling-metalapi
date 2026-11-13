#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Install the binary overlay into a matching, user-writable Darling GUI prefix."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True, type=Path, help="Darling installation prefix, not DPREFIX")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    prefix = args.prefix.resolve()
    if not (prefix / "bin/darling").is_file():
        parser.error("the installation must contain bin/darling; install the pinned Darling GUI runtime first")
    manifest = json.loads((ROOT / "build-info.json").read_text())
    files = manifest["overlay_files"]
    for relative in files:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            parser.error("invalid path in overlay manifest")
        if not (ROOT / "overlay" / path).is_file() or not (prefix / path).is_file():
            parser.error(f"missing source or existing runtime file: {path}")
    if args.dry_run:
        print("Validated", len(files), "overlay files for", prefix)
        return
    backup = prefix / (".darling-metalapi-backup-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    for relative in files:
        path = Path(relative)
        destination = backup / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(prefix / path, destination)
    for relative in files:
        shutil.copy2(ROOT / "overlay" / relative, prefix / relative)
    print("Installed", len(files), "files. Original files:", backup)


if __name__ == "__main__":
    main()
