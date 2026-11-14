# v0.3.0 validation — 2026-11-14

The release is an experimental Linux x86_64 binary overlay for the pinned
Darling GUI runtime. The full runtime and host dependencies are not included.

- Complete local Darling GUI build and local installation: passed.
- Native preparation check: all 16 commands met their expected status,
  including rejection of invalid shader source; Mesa lavapipe Vulkan ICD.
- Extracted archive's demo, using the matching local runtime and Intel Iris Xe:
  triangle offscreen, shapes offscreen and shapes window/resize/close all exited 0.
- Triangle readback: 57,408 background and 8,128 triangle pixels.
- Shapes readback at t = 0.0, 0.7, 1.4, 2.1: respectively 253,164, 253,255,
  253,298 and 253,269 checked pixels, zero mismatches. Pixels near mesh
  boundaries are excluded from the analytic comparison.
- The same runs check source compilation, function lookup, pipeline creation,
  invalid-source errors, unsupported options/resources, and compute buffer
  output at Metal index 5.
- Window test: 900x560 → 900x600 → 640x420, 180 submitted frames over 3.10 s,
  clean close. This short run is not a performance guarantee.
- Archive extraction, all five overlay-file replacements and original-file
  backups: passed in a disposable installation fixture.
- Source integration: prepare.py --check and prepare.py passed on clean
  checkouts of every pinned target; patched files and demo matched the
  validated working sources byte-for-byte.
- Source script syntax checks and diff whitespace checks: passed.
- Separate upstream native MSAA test: all six 1x/4x clear/draw cases passed
  on lavapipe. MSAA is not enabled in the released demo.

The supplied screenshot and six-second H.264 video show the actual demo window.
The recording is 950x668, 90 frames at 15 FPS; capture rate is independent of
render rate. Media were captured during the preceding implementation check.

Known upstream runtime messages include an unavailable /Users shader cache,
font/backend notices and an unimplemented orderedWindowNumbers query on close.
They do not change the recorded test outcomes. No compatibility with unrelated
Darling versions, older host runtimes, other GPU combinations or arbitrary Metal
applications is claimed.

## Added in 0.2.0

- Indexed 3D cube, perspective, GPU rotation and Depth32Float: both face orders
  matched 1,212,376 reference pixels each, excluding a narrow edge band.
- Concrete/wood flat preview and cube UV: four scenes, 129,422 sampled pixels,
  zero mismatches; wrong-material negative controls rejected each scene.
- Asymmetric 2x2 upload/orientation, nearest, linear and mixed fragment
  buffer/texture/sampler descriptors passed.
- Material buttons, resize and close passed the window test. The user independently
  confirmed both materials switch with normal mouse clicks.
- Fixed initial MTKView drawable size, initial child-layer window coordinates
  and nonzero viewport originY in the correct framework/backend layers.
- Native preparation commands and old triangle/shapes/cube checks passed.

## Added in 0.3.0

- Upstream Metal updated from 51bc193 to 643f571 (14 commits). Independent
  public API checks cover compile-options value/copy behavior, lazy initialization,
  device capability queries, enqueue and waitUntilScheduled.
- Fresh mslc builds: 2,573/2,573 tests pass after the read_write extension.
  The unchanged Indium corpus compiles and passes spirv-val 7/7 before and after.
  Compiler changes were independently reviewed; negative probes cover sampling,
  invalid coordinates/value types, helper access mismatch and mip rejection.
- GPU storage read/write/read_write: 8x8 and 7x5 RGBA8Unorm. Write replaces
  poison pixels; read returns normalized channels; in-place R/B swap matches
  the CPU reference, and a second pass restores the original. Minimal usage
  flags are exercised. Full 4x4 groups with bounds guards handle odd sizes;
  nonuniform dispatchThreads is not claimed.
- Explicit nearest/linear and embedded constexpr linear sampling pass. An
  external nearest sampler does not override the embedded linear sampler.
- Four dynamically lit material scenes: 129,436 reference samples, zero
  mismatches away from edges; wrong-light negative controls reject all four.
  Moving the lamp at fixed geometry changes 69,791 pixels while the albedo
  preview remains byte-identical. The unlit 129,422-sample checks also pass.
- Prior triangle/shapes/cube regressions pass on the refreshed Metal base.

Limits: these GPU storage/lighting tests cover the released 2D float texture
path on Intel Iris Xe. Compiler probes cover half and the existing uint scalar
write path; arbitrary formats, uint4 writes, mip/array/cube storage operations
and arbitrary compile options are not claimed. Lighting is a point-light demo,
not a physically based renderer or a claim of complete Metal compatibility.

The v0.3.0 lavapipe guest run passes the storage read/write/read_write kernels
on both sizes but fails the existing nearest-corner material sampling check
(mode 0, pixel 0,0: blue channel 255 instead of 0). It is not counted as a
passing full material run. Intel Iris Xe passes that same strict sampling test
and the complete lit/unlit scenes. Cross-driver material sampling remains a
known coverage/compatibility gap; no test was weakened or removed.

Final refreshed runtime: full GUI build/local install pass, 16/16 native
preparation checks pass, and material/light buttons, resize and close pass
(177 frames in 3.11 s). Short frame counts are not performance guarantees.

Release artifact check: the extracted v0.3.0 archive passes textures-offscreen,
textures-window-test, cube-offscreen and shapes-window-test on Intel Iris Xe.
All five overlay SHA-256 values match after installation in a disposable
fixture, with original files preserved. prepare.py --check leaves the target
unchanged; actual clean integration reproduces the Metal, Indium, demo and
patched compiler sources byte-for-byte. The 6-second v0.3.0 window recording
is 1050x758, 90 frames at 15 FPS; the README GIF is derived from that capture.
