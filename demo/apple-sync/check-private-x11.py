#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run native menu regressions on a private Xvfb, never on the desktop display."""
import argparse
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xvfb', type=Path, default=shutil.which('Xvfb'))
    parser.add_argument('--runner', type=Path, default=Path(__file__).resolve().parents[1] / 'run-render.py')
    parser.add_argument('--darling-prefix', type=Path, help='required when --runner points to the release run.py')
    parser.add_argument('--demo', type=Path)
    parser.add_argument('--output', type=Path, default=Path('results/appkit-input'))
    args = parser.parse_args()
    if not args.xvfb or not Path(args.xvfb).is_file():
        parser.error('install Xvfb or pass --xvfb /path/to/Xvfb')
    output = args.output.resolve();output.mkdir(parents=True, exist_ok=True)
    host = Path(__file__).with_name('check-x11-menu.py')
    command = [sys.executable, str(args.runner.resolve())]
    extra = []
    if args.darling_prefix: extra += ['--darling-prefix', str(args.darling_prefix.resolve())]
    if args.demo: extra += ['--demo', str(args.demo.resolve())]
    with (output / 'xvfb.log').open('w') as server_log:
        server = subprocess.Popen([str(Path(args.xvfb).resolve()), '-displayfd', '1', '-screen', '0',
                                   '1280x900x24', '-nolisten', 'tcp', '-noreset'],
                                  stdout=subprocess.PIPE, stderr=server_log, text=True)
        try:
            if not select.select([server.stdout], [], [], 8)[0]:
                raise RuntimeError('Xvfb did not start; see xvfb.log')
            display = server.stdout.readline().strip()
            if not display.isdigit(): raise RuntimeError('Xvfb startup failed; see xvfb.log')
            environment = dict(os.environ, DISPLAY=':' + display, DARLING_APPKIT_BACKEND='x11')
            environment.pop('WAYLAND_DISPLAY', None);environment.pop('XAUTHORITY', None)
            environment['METALAPI_PRIVATE_X11'] = environment['DISPLAY']
            for case in ('normal', 'grab-focus', 'popup-focus', 'alert', 'popup-alert'):
                mode = 'apple-menu-alert-test' if case in ('alert', 'popup-alert') else 'apple-menu-raw-test'
                with (output / (case + '-app.log')).open('w') as app_log, (output / (case + '-host.log')).open('w') as host_log:
                    app = subprocess.Popen(command + [mode] + extra, env=environment, stdout=app_log,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                    try:
                        driver = [sys.executable, str(host)]
                        if case == 'grab-focus': driver += ['--grab-focus-events']
                        if case in ('popup-focus', 'popup-alert'): driver += ['--popup-focus-transfer']
                        result = subprocess.run(driver, env=environment, stdout=host_log,
                                                stderr=subprocess.STDOUT, timeout=12)
                        status = app.wait(timeout=20)
                        if result.returncode or status:
                            raise RuntimeError(case + ' failed; see ' + str(output))
                        print('PASS private X11:', case, flush=True)
                    finally:
                        if app.poll() is None:
                            os.killpg(app.pid, signal.SIGTERM)
                            try: app.wait(timeout=3)
                            except subprocess.TimeoutExpired:
                                os.killpg(app.pid, signal.SIGKILL);app.wait()
        finally:
            server.terminate()
            try: server.wait(timeout=5)
            except subprocess.TimeoutExpired: server.kill();server.wait()


if __name__ == '__main__':
    main()
