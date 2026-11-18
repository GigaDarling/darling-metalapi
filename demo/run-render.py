#!/usr/bin/env python3
"""Run the public Metal client in an isolated rootless Darling prefix."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("mode", choices=["offscreen", "window", "window-test", "shapes-offscreen", "shapes-window", "shapes-window-test",
                                     "cube-offscreen", "cube-window", "cube-window-test",
                                     "textures-offscreen", "textures-window", "textures-window-test",
                                     "model-window", "model-offscreen", "doom-window", "apple-window", "apple-window-test", "apple-library-test", "apple-menu-test", "apple-menu-raw-test", "apple-menu-alert-test"])
parser.add_argument("--icd", type=Path, help="Vulkan ICD matching the desktop OpenGL GPU")
parser.add_argument("--output", type=Path, help="PPM output; defaults to offscreen.ppm or shapes.ppm in results")
parser.add_argument("--model", type=Path, help="prepared model pack for the 3D viewer")
parser.add_argument("--wad", type=Path, help="external DOOM IWAD for doom-window")
parser.add_argument("--state-dir", type=Path, help="persistent Doom configuration/save directory")
parser.add_argument("--engine-args", nargs=argparse.REMAINDER, default=[], help="extra Doom options; must be last")
args = parser.parse_args()

if args.mode.startswith("model-"):
    lab = root / "build/metal-baseline"
    command = [os.sys.executable, str(root / "tools/metal-baseline/model/run.py"),
               "--darling-prefix", str(lab / "prefix"), "--app",
               str(lab / "darling/src/tools/model/model-viewer.app/Contents/MacOS/model-viewer")]
    if args.mode == "model-offscreen": command += ["--offscreen", str(args.output or lab / "results/model.ppm")]
    if args.model: command += ["--model", str(args.model)]
    if args.icd: command += ["--icd", str(args.icd)]
    raise SystemExit(subprocess.call(command))

if args.mode == "doom-window":
    if not args.wad:
        parser.error("doom-window requires --wad /path/to/doom1.wad")
    lab = root / "build/metal-baseline"
    command = [os.sys.executable, str(root / "tools/metal-baseline/doom/run.py"),
               "--darling-prefix", str(lab / "prefix"), "--app",
               str(lab / "darling/src/tools/doom/doom-metal.app/Contents/MacOS/doom-metal"),
               "--wad", str(args.wad)]
    if args.icd: command += ["--icd", str(args.icd)]
    if args.state_dir: command += ["--state-dir", str(args.state_dir)]
    if args.engine_args: command += ["--", *args.engine_args]
    raise SystemExit(subprocess.call(command))

build = root / "build/metal-baseline"
launcher = build / "prefix/bin/darling"
demo = build / ("darling/src/tools/apple-metal-sample.app/Contents/MacOS/apple-metal-sample"
                if args.mode.startswith("apple-") else "darling/src/tools/metal-baseline-demo")
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
           "exec", str(demo)]
command += (["--menu-alert-test"] if args.mode=="apple-menu-alert-test" else ["--menu-raw-test"] if args.mode=="apple-menu-raw-test" else ["--menu-test"] if args.mode=="apple-menu-test" else ["--test"] if args.mode=="apple-window-test" else ["--library-test"] if args.mode=="apple-library-test" else [] if args.mode=="apple-window" else ["--"+args.mode])
if args.mode.endswith("offscreen"):
    name = "textures.ppm" if args.mode.startswith("textures-") else "cube.ppm" if args.mode.startswith("cube-") else "shapes.ppm" if args.mode.startswith("shapes-") else "offscreen.ppm"
    output = (args.output or build / "results" / name).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command.append("/Volumes/SystemRoot" + str(output))
print("Isolated prefix:", environment["DPREFIX"], flush=True)
raise SystemExit(subprocess.call(command, env=environment, cwd=root))
