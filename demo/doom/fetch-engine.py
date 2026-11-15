#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fetch the pinned, externally licensed DoomGeneric build dependency."""
import argparse
from pathlib import Path
import subprocess
import tempfile

REVISION = "e257a09527062bfb986b6e5e0780839b6cbd5b71"
URL = "https://github.com/ozkl/doomgeneric.git"


def fetch(destination):
    destination = destination.resolve()
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="doom-engine-", dir=destination.parent) as temp:
            checkout = Path(temp) / "source"
            subprocess.run(["git", "clone", "--no-checkout", URL, str(checkout)], check=True)
            subprocess.run(["git", "-C", str(checkout), "checkout", "--detach", REVISION], check=True)
            checkout.rename(destination)
    revision = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
    status = subprocess.check_output(["git", "-C", str(destination), "status", "--porcelain"], text=True)
    if revision != REVISION or status:
        raise RuntimeError("DoomGeneric dependency must be clean and at " + REVISION)
    if not (destination / "LICENSE").is_file():
        raise RuntimeError("DoomGeneric license is missing")
    print("Verified DoomGeneric:", REVISION, destination)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()
    fetch(args.destination)
