#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the Metal demo with a specified Darling installation in a rootless namespace."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("mode", choices=["offscreen", "window", "window-test", "shapes-offscreen", "shapes-window", "shapes-window-test",
                                     "cube-offscreen", "cube-window", "cube-window-test"])
parser.add_argument("--darling-prefix", required=True, type=Path)
parser.add_argument("--demo", type=Path, default=ROOT / "bin/metal-baseline-demo")
parser.add_argument("--icd", type=Path, help="Vulkan ICD matching the desktop OpenGL GPU")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
launcher = args.darling_prefix.resolve() / "bin/darling"
demo = args.demo.resolve()
if not launcher.is_file() or not demo.is_file():
    parser.error("missing Darling launcher or demo; see README.md")
environment = dict(os.environ, DARLING_NOOVERLAYFS="1")
if args.icd:
    if not args.icd.is_file():
        parser.error("ICD manifest does not exist")
    environment["VK_DRIVER_FILES"] = str(args.icd.resolve())
with tempfile.TemporaryDirectory(prefix="metalapi-") as temporary:
    environment["DPREFIX"] = temporary
    command = ["unshare", "--user", "--map-auto", "--map-root-user", "--mount", "--pid",
               "--fork", "--mount-proc", "setpriv", "--clear-groups", str(launcher),
               "exec", str(demo), "--" + args.mode]
    if args.mode.endswith("offscreen"):
        name = "cube.ppm" if args.mode.startswith("cube-") else "shapes.ppm" if args.mode.startswith("shapes-") else "triangle.ppm"
        output = (args.output or Path.cwd() / "results" / name).resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        command.append("/Volumes/SystemRoot" + str(output))
    result = subprocess.run(command, env=environment)
raise SystemExit(result.returncode)
