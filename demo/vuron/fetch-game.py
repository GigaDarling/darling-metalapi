#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fetch the pinned, externally licensed Vuron build dependency."""
import argparse
from pathlib import Path
import subprocess
import tempfile

REVISION = "bfced3abaf1b579051a060d144ab4d706551075c"
URL = "https://github.com/VanadiumVox/Vuron.git"


def fetch(destination):
    destination = destination.resolve()
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="vuron-source-", dir=destination.parent) as temp:
            checkout = Path(temp) / "source"
            subprocess.run(["git", "clone", "--no-checkout", URL, str(checkout)], check=True)
            subprocess.run(["git", "-C", str(checkout), "checkout", "--detach", REVISION], check=True)
            checkout.rename(destination)
    revision = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
    status = subprocess.check_output(["git", "-C", str(destination), "status", "--porcelain"], text=True)
    if revision != REVISION or status:
        raise RuntimeError("Vuron dependency must be clean and at " + REVISION)
    if not (destination / "LICENSE").is_file():
        raise RuntimeError("Vuron license is missing")
    print("Verified Vuron:", REVISION, destination)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()
    fetch(args.destination)
