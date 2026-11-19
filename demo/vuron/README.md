# Vuron on Darling Metal — 0.7.0

[Vuron](https://github.com/VanadiumVox/Vuron) is Varun Verma's MIT-licensed
macOS movement/shooter sandbox. This integration builds its actual C++ game,
Metal renderer, MSL shader, collision/weapon logic and Sandbox.map as a Mach-O
application running inside Darling. It retains the upstream retro, flat-shaded
appearance and textures; the game renders its geometry on the GPU.

Pinned source: `bfced3abaf1b579051a060d144ab4d706551075c`. The external checkout
is fetched and checked by `fetch-game.py`; it is not a fork on a GitHub account.
The binary package includes corresponding original source and its MIT license.
The bundled stb_image retains its embedded MIT/public-domain notice.

## Run

After source integration and `build.py`:

```sh
python3 run.py vuron-window \
  --darling-prefix work/darling/build/metal-baseline/prefix \
  --demo work/darling/build/metal-baseline/darling/src/tools/vuron/vuron.app/Contents/MacOS/vuron-game \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

For the compiled package, omit `--demo`. Replace the ICD path for another GPU;
the desktop compositor and Vulkan renderer must use the same GPU.

- Click the scene to capture the mouse. Escape releases it; clicking captures again.
- WASD: move. Mouse: look. Space: jump. Shift: crouch/fast fall.
- R or double-tap a movement key: acceleration.
- Left mouse: grapple/fire. Hold G: switch weapon. Right mouse: parry.
- E: katana. Command+Q or the window close button: quit.

Focus loss releases capture and clears held inputs. The initial click only
captures the mouse. The window remains open until the player closes it.
This is the upstream gameplay sandbox, not a completed campaign game.

## Adaptations and compatibility fixes

`prepare.py` creates build copies without editing the pinned checkout: correct
an AppKit import's case for Linux's filesystem; add click-to-capture/Escape and
focus-loss release; set the window title/position and enable mouse-motion events.
The original geometry, textures, physics, weapons and Metal shader remain intact.

General framework/compiler fixes are at their owning layers:

- mslc lowers `dfdx` and `dfdy` to SPIR-V derivative operations, preserving
  fragment-only and floating scalar/vector restrictions.
- AppKit exposes modern modifier names and the full-width all-events mask.
- QuartzCore's CAMetalLayer header exposes the CAMetalDrawable protocol.
- CoreGraphics remote-operation declarations have C linkage in Objective-C++.

These are public API behavior and declarations, without game-name checks.
The bundled shader uses float32 derivatives. Half derivatives currently use
float32 widening/narrowing; native Apple half precision parity is unmeasured.

## Verification

`derivatives-test.mm` renders independent linear functions of framebuffer x/y
into RGBA32Float, reads all four distinct lanes back, and checks derivative
magnitude/sign and fwidth. Intel Iris Xe and lavapipe each checked 43,200 values
without mismatch. A deliberately swapped-axis shader fails 14,400 comparisons.
48 derivative/fwidth compiler probes pass, including stage/type/arity rejection
and half scalar/vector lowering. An independent reviewer checked the compiler
change. `headers-test.mm` checks aliases/protocol visibility and links the mouse
function by address without changing input state.

```sh
python3 run.py vuron-derivatives \
  --darling-prefix /path/to/darling-prefix \
  --demo /path/to/metal-derivatives-test \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

The real Intel desktop window was inspected and the user confirmed movement,
mouse look, jumping, weapons and picture. Xvfb/lavapipe screenshots were black
for both Vuron and the known model viewer: they are not evidence of desktop
rendering. The independent lavapipe offscreen derivative test does pass.

Provenance: Vuron MIT source at the pinned revision; public
[Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf),
[SPIR-V specification](https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html),
and public AppKit/QuartzCore/CoreGraphics contracts. No restricted Apple source
or Apple binary analysis was used.
