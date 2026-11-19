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
                                     "cube-offscreen", "cube-window", "cube-window-test",
                                     "textures-offscreen", "textures-window", "textures-window-test",
                                     "vuron-window", "vuron-derivatives", "model-window", "model-offscreen", "doom-window", "apple-window", "apple-window-test", "apple-library-test", "apple-menu-test", "apple-menu-raw-test", "apple-menu-alert-test"])
parser.add_argument("--darling-prefix", required=True, type=Path)
parser.add_argument("--demo", type=Path, default=None)
parser.add_argument("--icd", type=Path, help="Vulkan ICD matching the desktop OpenGL GPU")
parser.add_argument("--output", type=Path)
parser.add_argument("--model", type=Path, help="prepared model pack for the 3D viewer")
parser.add_argument("--wad", type=Path, help="external DOOM IWAD for doom-window")
parser.add_argument("--state-dir", type=Path, help="persistent Doom configuration/save directory")
parser.add_argument("--engine-args", nargs=argparse.REMAINDER, default=[], help="extra Doom options; must be last")
args = parser.parse_args()

if args.mode.startswith("vuron-"):
    helper = ROOT / "demo/vuron/run.py"
    if not helper.is_file(): helper = ROOT / "source/demo/vuron/run.py"
    app = args.demo or ROOT / ("bin/vuron.app/Contents/MacOS/vuron-game" if args.mode == "vuron-window" else "bin/metal-derivatives-test")
    command = [os.sys.executable, str(helper), "--darling-prefix", str(args.darling_prefix), "--app", str(app)]
    if args.icd: command += ["--icd", str(args.icd)]
    raise SystemExit(subprocess.call(command))

if args.mode.startswith("model-"):
    helper = ROOT / "demo/model/run.py"
    if not helper.is_file(): helper = ROOT / "source/demo/model/run.py"
    app = args.demo or ROOT / "bin/model-viewer.app/Contents/MacOS/model-viewer"
    command = [os.sys.executable, str(helper), "--darling-prefix", str(args.darling_prefix), "--app", str(app)]
    if args.mode == "model-offscreen": command += ["--offscreen", str(args.output or Path.cwd() / "results/model.ppm")]
    if args.model: command += ["--model", str(args.model)]
    if args.icd: command += ["--icd", str(args.icd)]
    raise SystemExit(subprocess.call(command))

if args.mode == "doom-window":
    if not args.wad:
        parser.error("doom-window requires --wad /path/to/doom1.wad")
    helper = ROOT / "demo/doom/run.py"
    if not helper.is_file():
        helper = ROOT / "source/demo/doom/run.py"
    app = args.demo or ROOT / "bin/doom-metal.app/Contents/MacOS/doom-metal"
    command = [os.sys.executable, str(helper), "--darling-prefix", str(args.darling_prefix),
               "--app", str(app), "--wad", str(args.wad)]
    if args.icd: command += ["--icd", str(args.icd)]
    if args.state_dir: command += ["--state-dir", str(args.state_dir)]
    if args.engine_args: command += ["--", *args.engine_args]
    raise SystemExit(subprocess.call(command))

launcher = args.darling_prefix.resolve() / "bin/darling"
demo = (args.demo or ROOT / ("bin/apple-metal-sample.app/Contents/MacOS/apple-metal-sample"
                              if args.mode.startswith("apple-") else "bin/metal-baseline-demo")).resolve()
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
               "exec", str(demo)]
    command += (["--menu-alert-test"] if args.mode=="apple-menu-alert-test" else ["--menu-raw-test"] if args.mode=="apple-menu-raw-test" else ["--menu-test"] if args.mode=="apple-menu-test" else ["--test"] if args.mode=="apple-window-test" else ["--library-test"] if args.mode=="apple-library-test" else [] if args.mode=="apple-window" else ["--"+args.mode])
    if args.mode.endswith("offscreen"):
        name = "textures.ppm" if args.mode.startswith("textures-") else "cube.ppm" if args.mode.startswith("cube-") else "shapes.ppm" if args.mode.startswith("shapes-") else "triangle.ppm"
        output = (args.output or Path.cwd() / "results" / name).resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        command.append("/Volumes/SystemRoot" + str(output))
    result = subprocess.run(command, env=environment)
raise SystemExit(result.returncode)
