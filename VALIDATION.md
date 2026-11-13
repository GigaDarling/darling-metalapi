# v0.2.0 validation — 2026-11-14

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
