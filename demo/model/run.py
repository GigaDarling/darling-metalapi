#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the model viewer with an isolated Darling prefix."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--darling-prefix",required=True,type=Path)
    parser.add_argument("--app",required=True,type=Path)
    parser.add_argument("--model",type=Path)
    parser.add_argument("--offscreen",type=Path)
    parser.add_argument("--icd",type=Path)
    args=parser.parse_args()
    launcher=args.darling_prefix.resolve()/"bin/darling";app=args.app.resolve()
    if not launcher.is_file() or not app.is_file(): parser.error("Darling launcher and model viewer must exist")
    env=dict(os.environ,DARLING_NOOVERLAYFS="1")
    if args.icd:
        if not args.icd.is_file(): parser.error("Vulkan ICD does not exist")
        env["VK_DRIVER_FILES"]=str(args.icd.resolve())
    with tempfile.TemporaryDirectory(prefix="metalapi-model-") as prefix:
        env["DPREFIX"]=prefix
        command=["unshare","--user","--map-auto","--map-root-user","--mount","--pid","--fork","--mount-proc",
                 "setpriv","--clear-groups",str(launcher),"exec",str(app)]
        if args.model:
            if not args.model.is_file(): parser.error("model pack does not exist")
            command += ["--model","/Volumes/SystemRoot"+str(args.model.resolve())]
        if args.offscreen:
            output=args.offscreen.resolve();output.parent.mkdir(parents=True,exist_ok=True)
            command += ["--offscreen","/Volumes/SystemRoot"+str(output)]
        process=subprocess.Popen(command,env=env,stdin=subprocess.DEVNULL,start_new_session=True)
        try: return process.wait(timeout=120 if args.offscreen else None)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL);process.wait()
            print("FAIL model test timed out")
            return 124


if __name__=="__main__": raise SystemExit(main())
