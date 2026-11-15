#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Download and verify the original DOOM 1.9 shareware archive locally."""
import argparse
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.request import urlopen
import zipfile

URL = "https://ftp.gwdg.de/pub/misc/ftp.idsoftware.com/idstuff/doom/doom19s.zip"
ARCHIVE_SHA256 = "cacf0142b31ca1af00796b4a0339e07992ac5f21bc3f81e7532fe1b5e1b486e6"
WAD_SHA256 = "1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/doom-data"))
    args = parser.parse_args()
    target = args.output.resolve()
    wad = target / "doom1.wad"
    if wad.exists():
        if hashlib.sha256(wad.read_bytes()).hexdigest() != WAD_SHA256:
            parser.error("existing doom1.wad differs; choose a new output directory")
        print("Verified existing shareware WAD:", wad)
        return
    bsdtar = shutil.which("bsdtar")
    if not bsdtar:
        parser.error("install libarchive/bsdtar to extract the original shareware package")
    with urlopen(URL, timeout=60) as response:
        archive = response.read(4 * 1024 * 1024)
    if hashlib.sha256(archive).hexdigest() != ARCHIVE_SHA256:
        parser.error("shareware archive checksum mismatch")
    with zipfile.ZipFile(io.BytesIO(archive)) as original:
        installer = original.read("DOOMS_19.1") + original.read("DOOMS_19.2")
    # Concatenated original parts form a self-extracting ZIP. Never execute it.
    with tempfile.TemporaryDirectory(prefix="doom-shareware-") as temp:
        path = Path(temp) / "installer.exe"
        path.write_bytes(installer)
        content = {name: subprocess.check_output([bsdtar, "-xOf", str(path), name])
                   for name in ("DOOM1.WAD", "README.TXT", "HELPME.TXT")}
    if hashlib.sha256(content["DOOM1.WAD"]).hexdigest() != WAD_SHA256:
        parser.error("shareware WAD checksum mismatch")
    target.mkdir(parents=True, exist_ok=True)
    (target / "doom19s.zip").write_bytes(archive)
    for name, data in content.items():
        (target / name.lower()).write_bytes(data)
    print("Downloaded unmodified DOOM 1.9 shareware:", wad)
    print("Original archive and accompanying notices kept in", target)


if __name__ == "__main__":
    main()
