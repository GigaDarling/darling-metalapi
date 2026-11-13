#!/usr/bin/env python3
"""Recheck preparation steps 1–2; never installs Darling or submits a draw."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
LAB = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build/metal-baseline")
    parser.add_argument("--icd", type=Path, help="Vulkan ICD manifest for this check only")
    args = parser.parse_args()
    build = args.build_dir.resolve()
    results = build / "results"
    results.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    if args.icd:
        if not args.icd.is_file():
            parser.error("ICD manifest does not exist")
        environment["VK_DRIVER_FILES"] = str(args.icd.resolve())

    records = []
    passed = False

    def run(name, command, expected=0, env=None):
        command = [str(part) for part in command]
        result = subprocess.run(command, cwd=ROOT, env=env or environment,
                                capture_output=True, text=True, timeout=120)
        (results / (name + ".log")).write_text(result.stdout + result.stderr)
        records.append({"name": name, "command": command,
                        "exit": result.returncode, "expected_exit": expected})
        if result.returncode != expected:
            raise RuntimeError(f"{name}: exit {result.returncode}; see {results / (name + '.log')}")
        print(f"PASS {name}", flush=True)
        return result.stdout

    try:
        headless = dict(environment)
        headless.pop("DISPLAY", None)
        headless.pop("WAYLAND_DISPLAY", None)
        run("vulkan-summary", ["vulkaninfo", "--summary"], env=headless)
        run("vulkan-features", ["vulkaninfo"], env=headless)

        indium = ROOT / "src/external/metal/deps/indium"
        run("build-library-probe", [
            *shlex.split(os.environ.get("CXX", "clang++")),
            "-std=c++17", "-Wall", "-Wextra", "-Werror",
            "-I" + str(indium / "include"), LAB / "library-probe.cpp",
            "-L" + str(build / "indium"), "-Wl,-rpath," + str(build / "indium"),
            "-lindium", "-o", build / "library-probe",
        ])

        for stage in ("vertex", "fragment"):
            name = "baseline_" + stage
            module = build / ("baseline-" + stage + ".spv")
            reflection = build / ("baseline-" + stage + ".json")
            run("compile-" + stage, [build / "mslc/mslc",
                LAB / "shaders" / ("baseline-" + stage + ".metal"),
                "-o", module, "--reflect", reflection, "--validate"])
            run("validate-" + stage, ["spirv-val", "--target-env", "vulkan1.3", module])
            document = json.loads(reflection.read_text())
            entries = document.get("entry_points", [])
            if document.get("reflection_version") != 2 or len(entries) != 1:
                raise RuntimeError("unexpected mslc reflection version or entry-point count")
            entry = entries[0]
            if (entry.get("name") != name or entry.get("stage") != stage
                    or entry.get("bindings") != [] or entry.get("embedded_samplers") != []):
                raise RuntimeError("the binding-free probe cannot describe this shader's reflection")
            run("load-" + stage, [build / "library-probe", stage, name, module])

        # A compiler that reports success for every input must not pass this check.
        with tempfile.TemporaryDirectory(prefix="invalid-shader-", dir=build) as temporary:
            invalid = Path(temporary) / "invalid.metal"
            invalid.write_text("fragment float4 broken( {\n")
            run("reject-invalid-source", [build / "mslc/mslc", invalid,
                "-o", Path(temporary) / "invalid.spv"], expected=1)

        for topic in ("device-info", "lazy-device", "basic-compute-mslc",
                      "store-reference", "encoder-interface"):
            run(topic, [build / "indium/test" / topic / ("indium-test-" + topic)])
        run("iridium-unit-tests", ["ctest", "--test-dir", build / "indium",
                                  "-R", "^(vector-types|vector-splat)$", "--output-on-failure"])
        passed = True
    finally:
        (results / "summary.json").write_text(json.dumps({
            "passed": passed, "vulkan_icd": environment.get("VK_DRIVER_FILES"),
            "checks": records,
        }, indent=2) + "\n")
    print(f"Results: {results}")


if __name__ == "__main__":
    main()
