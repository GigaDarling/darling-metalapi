#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Play the Doom Metal application through Darling using an external IWAD."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--darling-prefix", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--wad", required=True, type=Path)
    parser.add_argument("--state-dir", type=Path, default=Path.home() / ".local/share/darling-metalapi/doom")
    parser.add_argument("--icd", type=Path)
    parser.add_argument("engine_args", nargs=argparse.REMAINDER, help="extra Doom options after --")
    args = parser.parse_args()
    launcher = args.darling_prefix.resolve() / "bin/darling"
    app, wad = args.app.resolve(), args.wad.resolve()
    if not all(path.is_file() for path in (launcher, app, wad)):
        parser.error("Darling launcher, Doom executable and WAD must exist")
    with wad.open("rb") as stream:
        signature = stream.read(4)
    if signature != b"IWAD":
        parser.error("--wad must be an IWAD, such as the unmodified shareware doom1.wad")
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, DARLING_NOOVERLAYFS="1")
    if args.icd:
        if not args.icd.is_file():
            parser.error("Vulkan ICD does not exist")
        environment["VK_DRIVER_FILES"] = str(args.icd.resolve())
    if "PULSE_SERVER" not in environment and environment.get("XDG_RUNTIME_DIR"):
        environment["PULSE_SERVER"] = "unix:" + environment["XDG_RUNTIME_DIR"] + "/pulse/native"
    extra = args.engine_args[1:] if args.engine_args[:1] == ["--"] else args.engine_args
    with tempfile.TemporaryDirectory(prefix="metalapi-doom-") as temporary:
        environment["DPREFIX"] = temporary
        command = ["unshare", "--user", "--map-auto", "--map-root-user", "--mount", "--pid",
                   "--fork", "--mount-proc", "setpriv", "--clear-groups", str(launcher),
                   "exec", str(app), "--state-dir", "/Volumes/SystemRoot" + str(state),
                   "-iwad", "/Volumes/SystemRoot" + str(wad), "-nomusic", *extra]
        print("DOOM state and saves:", state, flush=True)
        return subprocess.call(command, env=environment)


if __name__ == "__main__":
    raise SystemExit(main())
