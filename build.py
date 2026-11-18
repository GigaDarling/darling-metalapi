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
engine = darling / "build/metal-baseline/vendor/doomgeneric"
subprocess.run([os.sys.executable, str(ROOT / "demo/doom/fetch-engine.py"),
                "--destination", str(engine)], check=True)
model_source = darling / "build/metal-baseline/vendor/FlightHelmet"
model_pack = darling / "build/metal-baseline/models/FlightHelmet.dmodel"
subprocess.run([os.sys.executable, str(ROOT / "demo/model/fetch-sample.py"),
                "--destination", str(model_source)], check=True)
subprocess.run([os.sys.executable, str(ROOT / "demo/model/prepare-model.py"),
                str(model_source / "glTF/FlightHelmet.gltf"), "-o", str(model_pack),
                "--texture-size", "1024"], check=True)
# Xcode's offline shader build is replaced by the pinned native MIT compiler.
host_build = darling / "build/metal-baseline/mslc-host"
subprocess.run(["cmake", "-S", str(compiler), "-B", str(host_build),
                "-DCMAKE_BUILD_TYPE=Release"], check=True)
subprocess.run(["cmake", "--build", str(host_build), "--target", "mslc-cli",
                "--parallel", str(args.jobs)], check=True)
subprocess.run(["cmake", "-S", str(darling), "-B", str(build), "-G", "Ninja",
    "-DCMAKE_INSTALL_PREFIX=" + str(prefix), "-DCOMPONENTS=gui", "-DTARGET_i386=OFF",
    "-DENABLE_METAL=ON", "-DENABLE_TESTS=OFF", "-DDARLING_NO_CCACHE=ON",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DMSLC_SOURCE_DIR=" + str(compiler),
    "-DMSLC_EXECUTABLE=" + str(host_build / "mslc"),
    "-DDARLING_BUILD_METAL_DEMO=ON", "-DDOOMGENERIC_SOURCE_DIR=" + str(engine), "-DMODEL_ASSET_PACK=" + str(model_pack)], check=True)
subprocess.run(["cmake", "--build", str(build), "--parallel", str(args.jobs)], check=True)
environment = dict(os.environ, DESTDIR="/")
subprocess.run(["cmake", "--install", str(build)], env=environment, check=True)
print("Built local runtime:", prefix)
print("Demo:", build / "src/tools/metal-baseline-demo")
