#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build an already integrated Darling checkout into a local prefix."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--darling", required=True, type=Path)
parser.add_argument("--jobs", type=int, default=4)
args = parser.parse_args()
darling = args.darling.resolve()
build = darling / "build/metal-baseline/darling"
prefix = darling / "build/metal-baseline/prefix"
manifest = json.loads((ROOT / "upstream.json").read_text())
compiler = (darling / "build/metal-baseline/vendor/mslc" if manifest["mslc"].get("patch")
            else ROOT / "deps/mslc")
if args.jobs < 1 or not (darling / "tools/metal-baseline/render-demo.mm").is_file():
    parser.error("use positive --jobs and run prepare.py on this checkout first")
subprocess.run(["cmake", "-S", str(darling), "-B", str(build), "-G", "Ninja",
    "-DCMAKE_INSTALL_PREFIX=" + str(prefix), "-DCOMPONENTS=gui", "-DTARGET_i386=OFF",
    "-DENABLE_METAL=ON", "-DENABLE_TESTS=OFF", "-DDARLING_NO_CCACHE=ON",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DMSLC_SOURCE_DIR=" + str(compiler),
    "-DDARLING_BUILD_METAL_DEMO=ON"], check=True)
subprocess.run(["cmake", "--build", str(build), "--parallel", str(args.jobs)], check=True)
environment = dict(os.environ, DESTDIR="/")
subprocess.run(["cmake", "--install", str(build)], env=environment, check=True)
print("Built local runtime:", prefix)
print("Demo:", build / "src/tools/metal-baseline-demo")
