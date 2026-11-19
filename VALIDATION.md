# v0.4.0 validation — 2026-11-15

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
- Archive extraction, all six overlay-file replacements and original-file
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

## Added in v0.4.0

- Official MIT Apple archive downloaded from docs-assets.developer.apple.com;
  all six Renderer files match the archived originals byte-for-byte. Hash and
  license are retained. Only generated host module-import syntax changes.
- Initial runtime fails on the sample's default library with "Invalid Metal
  library magic". The new general Darling SPIR-V container loader fixes the
  library/bundle path without rewriting Apple's renderer or shader logic.
- Original shader compiles unchanged and passes spirv-val.
- New library tests: URL, default/main/explicit bundle, contiguous and segmented
  dispatch data, function names/types, missing function; 36 invalid cases each
  tested both with NSError output and with nil error output. All pass on Intel.
- Official sample: 180 frames, real view resize 1000x600 → 800x500 → 640x420,
  completion semaphore continues across three reused buffers; clean close.
- Four independently checked images: 143396 + 143328 + 93707 + 62261 = 442692
  sampled pixels, zero mismatches, 35522 interior samples. Wrong phase rejected
  with 20519, 20478, 19803 and 15169 mismatches respectively.
- Drawable readback uses blit-to-buffer with padded row strides. A preliminary
  test attempted unsupported direct drawable getBytes; that test-harness error
  was corrected, and timer exceptions now fail the test explicitly.
- Portable loader syntax-checks with runtime mslc compilation disabled.
- These results cover a source-built, MIT example and Darling's own offline
  format; arbitrary Apple AIR libraries and complete Xcode app launch are not claimed.


### Native AppKit controls in v0.4.0

- Added real NSMenu/NSMenuItem, NSButton, editable NSTextField and mouse/key
  handling in the app bootstrap; original Apple renderer/shader files unchanged.
- A border-entry menu test failed before the hit-cache fix and passes after it.
- The real desktop click exposed normal focus transfer between this client's
  own windows; the initial synthetic test did not cover it. A private Xvfb test
  now transfers focus from a native child to the popup and checks the action.
- Five private-X11 cases pass, including NSAlert visibility/modal ownership and
  its OK result. Temporary grab focus events do not deactivate the application.
- The user confirmed the actual About dialog opens with a real click, and
  reported one-frame advance, editing-menu and context-menu checks as working.
- AppKit and its separate X11 backend plugin are both included in the local
  overlay (six files).


### Release recheck — 2026-11-15

The six prepared overlay binaries match the installed test runtime by SHA-256.
The packaged app passes apple-library-test and apple-window-test on Intel Iris Xe
under a private Xvfb; the previous textures-offscreen regression also passes.
All five private-X11 menu/focus/modal cases pass using the packaged app.
Clean pinned integration passes prepare.py --check without changing the target,
then actual preparation reproduces the released Metal and demo sources.
The official Apple ZIP hash and all six original Renderer files were rechecked.
Python syntax and final diff whitespace checks pass. The captured media precede
this recheck; test frame counts are not a performance guarantee.

The user then tested the actual packaged v0.4.0 executable on the desktop:
About opens a native dialog with OK, and View > One frame while paused advances
the visible counter by exactly one. Both were confirmed before publication.


## v0.5.0 DOOM

- DoomGeneric pinned to `e257a09527062bfb986b6e5e0780839b6cbd5b71`; clean checkout
  verified before build. Compiled into the same Mach-O app as the AppKit/Metal
  frontend and AudioQueue effect mixer.
- Original shareware 1.9 archive and extracted WAD SHA-256 verified; downloader
  tested in a new directory. No WAD is included in the distributable.
- Intel desktop frame inspected: E1M1 world, weapon, HUD and pickup message.
  The user confirmed movement, shooting and sound effects in the actual app.
- ASan/UBSan mixer tests pass: bounds, wrong format, truncation, stereo,
  saturation, sample-rate conversion and channel completion.
- ASan/UBSan input tests pass: repeat, aliased controls, releases after a menu
  transition, focus loss and invalid sources. LeakSanitizer is disabled because
  the execution sandbox does not support its process inspection.
- Initial launch implementation was moved onto the NSApplication run loop, with
  presentation deferred until initialization completes. No framework changes
  were needed. Xvfb/software presentation was not a valid image oracle here;
  Intel desktop output was used for visual validation.
- Music/MIDI/OPL and mouse-look are not implemented. This is software-rendered
  Doom with Metal presentation, not a Metal world renderer.

Final package smoke check: the packaged executable was launched through the
focused project's `run.py doom-window`, with an external IWAD and persistent
state directory. Intel E1M1 framebuffer and AudioQueue startup were verified.
The tools integration patch applied to the pinned pristine CMake file and
produced the exact local integration. Archive contents were checked for the
Doom executable, matching frontend sources, corresponding engine source and
license; no WAD or stale running executable is present.


## v0.6.0 complex 3D model

- Pinned CC0 Flight Helmet: original glTF, 3,227,148-byte geometry buffer and
  15 PNG hashes verified against `demo/model/sample-assets.json`.
- Prepared pack: 55,392 vertices, 94,722 triangles, six primitives/materials,
  15 images limited to 1024x1024, 67,597,032 bytes. Re-import after adding input
  validation produced an identical pack.
- Shader compiled with mslc and passed SPIR-V validation. The Mach-O application
  compiled against the existing Darling Metal runtime.
- Intel Iris Xe and lavapipe each passed three camera/aspect checks: 577, 571
  and 568 stable points (1,716 total), including all six materials. Zero
  mismatches against independent CPU ray/triangle nearest-hit results and
  zero mismatches with reversed primitive submission.
- Rotation changes the textured output; portrait resize uses a matching depth
  attachment. Blank-image negative control is rejected.
- 14 synthetic glTF import tests pass: interleaved accessors, uint16 indices,
  missing normals, GLB, transforms, quaternion rotation, inverse-transpose
  normals, bounds failures, bad indices, cycles, directory escape, required
  extensions, non-triangle geometry and unsupported transparency.
- Native pack checks pass with ASan/UBSan, including every truncation of a
  minimal fixture, invalid counts/indices/ranges/material/texture references,
  NaN, trailing data, and the real sample. LeakSanitizer is disabled because
  the execution sandbox does not support its process inspection.
- The real desktop window was visually inspected. The user confirmed the
  model, automatic rotation, dragging, zoom and pause. No desktop input was
  automated for that check.
- Source glTF/GLB conversion is host-side; guest loading uses the documented
  pack. Static opaque triangles are supported; refraction, skins, morphs,
  animation playback, sparse accessors and full material extensions are not.

## v0.7.0 Vuron

Vuron bfced3abaf1b579051a060d144ab4d706551075c is a clean, pinned MIT dependency.
Its original shader initially failed on unsupported dfdx; after adding general
fragment derivatives it compiles and passes SPIR-V validation. The C++/ObjC++
Mach-O application builds with generated platform adaptations; upstream shader,
geometry, textures, collision and weapons are retained.

48 derivative/fwidth probes pass, including new float and half scalar/vector
forms and illegal stage/type/arity cases. Independent review found no blocker
in the float32 path; its requested produced-value and half lowering coverage
were added. Native Apple half precision parity remains unmeasured.

Intel and lavapipe each pass 43,200 RGBA32Float produced-value comparisons for
independent x/y-linear functions with distinct lane slopes, including dfdy sign
and fwidth. An axis-swap mutant fails 14,400 comparisons on each driver.

The actual Intel desktop window was captured and visually checked. The user
confirmed movement, mouse look, jumping, weapons and picture. Xvfb/lavapipe
window captures are black for both this game and the known model viewer;
these captures are not claimed as successful windowed validation.

Release packaging check: Metal, MetalKit, QuartzCore and their Indium/Iridium
libraries were rebuilt together. The packaged model and Vuron windows were
recorded using the matching, installed Darling prefix; the showcase uses only
those application windows. Vuron's recorded arena view is static; interactive
controls were verified separately by the user. Moving an installed launcher
alone does not relocate Darling's compiled-in runtime paths.
