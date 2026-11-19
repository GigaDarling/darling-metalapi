#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Launch Vuron using the shared isolated Darling application runner."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[1] / "model/run.py"), run_name="__main__")
