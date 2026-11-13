#!/usr/bin/env python3
"""Run the public Metal client in an isolated rootless Darling prefix."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("mode", choices=["offscreen", "window", "window-test", "shapes-offscreen", "shapes-window", "shapes-window-test"])
parser.add_argument("--icd", type=Path, help="Vulkan ICD matching the desktop OpenGL GPU")
parser.add_argument("--output", type=Path, help="PPM output; defaults to offscreen.ppm or shapes.ppm in results")
args = parser.parse_args()
build = root / "build/metal-baseline"
launcher = build / "prefix/bin/darling"
demo = build / "darling/src/tools/metal-baseline-demo"
if not launcher.is_file() or not demo.is_file():
    parser.error("build the runtime, demo and local prefix first; see README.md")
environment = dict(os.environ)
environment["DPREFIX"] = tempfile.mkdtemp(prefix="runtime-" + args.mode + "-", dir=build)
environment["DARLING_NOOVERLAYFS"] = "1"
if args.icd:
    if not args.icd.is_file():
        parser.error("ICD manifest does not exist")
    environment["VK_DRIVER_FILES"] = str(args.icd.resolve())
command = ["unshare", "--user", "--map-auto", "--map-root-user", "--mount", "--pid",
           "--fork", "--mount-proc", "setpriv", "--clear-groups", str(launcher),
           "exec", str(demo), "--" + args.mode]
if args.mode.endswith("offscreen"):
    output = (args.output or build / "results" / ("shapes.ppm" if args.mode.startswith("shapes-") else "offscreen.ppm")).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command.append("/Volumes/SystemRoot" + str(output))
print("Isolated prefix:", environment["DPREFIX"], flush=True)
raise SystemExit(subprocess.call(command, env=environment, cwd=root))
