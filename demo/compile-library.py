#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile MSL to the open Darling SPIR-V library format (not Apple AIR)."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import tempfile

MAGIC = b"DMSLSPV\0"


def package(spirv, reflection):
    if len(spirv) < 20 or len(spirv) % 4 or spirv[:4] != b"\x03\x02\x23\x07":
        raise ValueError("expected a SPIR-V module")
    document = json.loads(reflection)
    if document.get("reflection_version") != 2 or not document.get("entry_points"):
        raise ValueError("expected mslc reflection version 2 with entry points")
    return struct.pack("<8s4I", MAGIC, 1, len(spirv), len(reflection), 0) + spirv + reflection


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("-o", "--output", required=True, type=Path)
    parser.add_argument("--mslc", required=True, type=Path)
    parser.add_argument("-I", dest="includes", action="append", default=[], type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="metalapi-library-") as temporary:
        spirv = Path(temporary) / "module.spv"
        reflection = Path(temporary) / "reflection.json"
        command = [str(args.mslc.resolve()), str(args.source.resolve()), "-o", str(spirv),
                   "--reflect", str(reflection), "--validate"]
        for path in args.includes:
            command += ["-I", str(path.resolve())]
        subprocess.run(command, check=True)
        payload = package(spirv.read_bytes(), reflection.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(payload)
    print("Built Darling SPIR-V library:", args.output)


if __name__ == "__main__":
    main()
