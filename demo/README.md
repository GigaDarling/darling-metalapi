# Metal preparation, shapes and a rotating 3D cube

This directory contains a native preparation check and a Mach-O client using
public Metal, MetalKit and AppKit APIs. The runtime client checks an offscreen
frame, or displays a triangle through MTKView/CAMetalLayer in an X11 window.
The shapes modes draw a square, a filled circle and a ring, with time-based
translation, rotation, scale and color changes through Metal vertex buffers.
The cube modes add indexed 3D geometry, perspective, GPU rotation about two axes
and depth-tested occlusion using an explicit Depth32Float attachment.
Generated files, the compiler checkout and isolated runtime prefixes live under
`build/metal-baseline/`. No system installation is performed.

The separate clean upstream checkout and a capability map for future work are
documented in [UPSTREAM-STUDY.md](UPSTREAM-STUDY.md).

## Rotating 3D cube

From the Darling repository root, after building the demo:

```sh
python3 tools/metal-baseline/run-render.py cube-window \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py cube-offscreen \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py cube-window-test \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

The independently authored cube uses 24 position/color vertices and 36 uint16
indices for six colored faces. MSL applies yaw and pitch from elapsed seconds,
then a 55-degree vertical perspective projection with a [0,1] depth range.
Geometry stays in buffer 3; the aspect ratio, projection and time use buffer 7.
The renderer uses public Metal APIs throughout. It creates its own depth texture
because MTKView's automatic depth attachment remains unimplemented. That texture
is reused between frames and replaced when the drawable size changes.
No additional framework or Vulkan backend changes were needed for this scene.

`cube-offscreen` checks t = 0.0, 0.7, 1.4 and 2.1 seconds, at 640x480 and
480x640. The reference intersects camera rays with the six planes of a box,
independently of the indexed mesh and GPU rasterizer. It checks every pixel
except a 1.5-pixel band near face boundaries/silhouettes. The two face submission
orders must agree away from that band: coincident edge samples do not have a
unique face color under a Less depth comparison. Both orders are compared with
the analytic reference. Negative controls must reject a blank image and a draw
with Always comparison and disabled depth writes.

Verified on Intel Iris Xe on 2026-11-13: each order checked 1,212,376 pixels
across four frames with zero mismatches; disabling depth comparison was detected
at all four times. Two or three faces were visible in each frame. The window
test submitted 180 frames, resized 900x560 → 900x600 → 640x420, and closed
cleanly. Existing shapes and triangle offscreen regressions also passed.
This does not constitute general validation of every depth/indexed-draw API.

Sources: public [indexed draw](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/drawindexedprimitives(type:indexcount:indextype:indexbuffer:indexbufferoffset:)),
[depth attachment](https://developer.apple.com/documentation/metal/mtlrenderpassdepthattachmentdescriptor)
and [depth comparison](https://developer.apple.com/documentation/metal/mtldepthstencildescriptor/depthcomparefunction)
contracts, the open mslc C API and existing Indium interfaces. No restricted
Apple source was used. Results and captured media live in
`build/metal-baseline/results/cube-*`.

Validated locally on 2026-11-13 with Clang/LLVM 23.1.5. The available device was
Mesa llvmpipe (CPU), Vulkan 1.4.354. Vulkan 1.3, timeline semaphores, buffer device
addresses, dynamic rendering and synchronization2 were available. The native
libraries and both x86_64 Mach-O frameworks (`Metal`, `MetalKit`) built
successfully with Metal enabled. All 16 commands in the preparation check met
their expected exit status, including the intentionally invalid shader.
Those native checks ran in the restricted environment. Outside it, Intel Iris Xe
and RTX 3050 devices were available. Runtime rendering was verified on Intel Iris
Xe, matching the desktop's Intel OpenGL renderer. The public Metal client read
back 65,536 pixels: 8,128 triangle pixels and 57,408 background pixels. The real
window screenshot contains 43,200 triangle pixels. Window checks passed at
720x480, 900x600 and 640x420, followed by a clean exit on close.
The shapes extension was checked at four fixed times: 0.0, 0.7, 1.4 and 2.1
seconds. Across those frames, 1,012,986 pixels away from the tessellated edges
matched the analytic reference with zero mismatches. The shapes window test
submitted 179 frames over 3.11 seconds (57.6 FPS including initialization),
resized twice and exited cleanly. This is a short observation on this machine,
not a performance guarantee. A six-second recording of the actual window is
`build/metal-baseline/results/shapes-animation.mp4`, captured at 15 FPS.

## Build the native backend and its preparation checks

From the repository root:

```sh
cmake -S src/external/metal/deps/indium -B build/metal-baseline/indium -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DENABLE_TESTS=ON \
  -DSTB_INCLUDE_DIRS=/usr/include/MaterialXRender/External/StbImage

cmake --build build/metal-baseline/indium --parallel 4 --target \
  indium indium_kit iridium mtl2spv \
  indium-test-device-info indium-test-lazy-device \
  indium-test-basic-compute-mslc indium-test-store-reference \
  indium-test-encoder-interface indium-test-vector-types indium-test-vector-splat
```

`STB_INCLUDE_DIRS` above is the existing header location on the validation machine.
On another installation use the directory containing `stb_image.h`. Indium's
all-tests configuration also needs the dependencies of the other example targets;
the backend libraries themselves can be built with `ENABLE_TESTS=OFF`.

## Build the source shader compiler

The external `mslc` tool is pinned to the revision checked in this task. It is
downloaded into the ignored build directory; no compiler source is vendored into
Darling's tracked source tree.

```sh
git clone https://github.com/cristim/mslc.git build/metal-baseline/vendor/mslc
git -C build/metal-baseline/vendor/mslc checkout --detach 6964bb3984e26de95bbca89b08f305a6c4ff3317

cmake -S build/metal-baseline/vendor/mslc -B build/metal-baseline/mslc -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
cmake --build build/metal-baseline/mslc --target mslc-cli --parallel 4
```

Run these clone commands only when that checkout does not already exist. The
tool's MIT license is retained in its checkout.

## Recheck the environment and shaders

```sh
python3 tools/metal-baseline/check.py \
  --icd /usr/share/vulkan/icd.d/lvp_icd.json
```

This explicitly selects Mesa's CPU Vulkan driver for this process tree. It does
not change the desktop's driver settings. Omit `--icd` to use the environment's
normal driver selection, or pass the intended GPU's manifest. The Vulkan summary
and feature report are captured without requiring an X11/Wayland connection.

The script compiles the two independently authored `.metal` fixtures with `mslc`,
validates their SPIR-V for Vulkan 1.3, checks their version-2 reflection documents,
and loads each into Indium using its existing SPIR-V + reflection interface.
The probe only handles these binding-free fixtures and rejects a reflection
document requiring resources. It verifies function lookup and rejection of
missing entries, empty reflection and truncated modules. Malformed source must
also fail compilation.

Five existing backend checks and two existing Iridium unit tests run afterward.
The compute check executes a shader over 16,777,216 elements and compares the
readback with a CPU reference; its negative controls verify that an incorrect
resource mapping fails. No window or render pipeline is exercised here.

Commands, exit statuses and logs are in `build/metal-baseline/results/`. Shader
artifacts are `baseline-vertex.spv`, `baseline-fragment.spv` and their `.json`
reflection files in the build directory.

## Build the Mach-O frameworks separately

```sh
cmake -S . -B build/metal-baseline/darling -G Ninja \
  -DCMAKE_INSTALL_PREFIX="$PWD/build/metal-baseline/prefix" \
  -DCOMPONENTS=gui -DTARGET_i386=OFF \
  -DENABLE_METAL=ON -DENABLE_TESTS=OFF -DDARLING_NO_CCACHE=ON \
  -DMSLC_SOURCE_DIR="$PWD/build/metal-baseline/vendor/mslc" \
  -DDARLING_BUILD_METAL_DEMO=ON \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build build/metal-baseline/darling --parallel 4
DESTDIR=/ cmake --install build/metal-baseline/darling
```

The configured install destination is inside the build directory. `DESTDIR=/`
keeps that destination while using the staged-install path, which avoids stopping
other Darling sessions. No sudo is used. Building all selected components is
necessary for launchd, shellspawn and the framework dependencies, beyond just the
Metal library targets.

## Run the public Metal client

```sh
python3 tools/metal-baseline/run-render.py offscreen \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py window-test \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py window \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

The runner creates a fresh copy-mode prefix each time. It uses a rootless user
namespace with subordinate UID/GID mappings and a matching `/proc`, and clears
only its own supplementary groups before starting the launcher. It requires
`unshare`, `setpriv`, `newuidmap`, `newgidmap` and configured subordinate IDs. The
validation machine already had these. It grants no host root privileges and
does not change system account or namespace settings.

Choose a Vulkan ICD matching the desktop OpenGL GPU: CAMetalLayer shares image
memory between Vulkan and OpenGL. The commands above name the validation
machine's Intel ICD. Other machines may need a different manifest.

`offscreen` verifies a clear-only frame and a rendered triangle by reading the
texture with Metal's getBytes API. It also checks source compilation, function
names, shader stages, invalid-source NSError handling and a null error output.
It executes a buffer-writing compute shader at Metal buffer index 5 and checks
its result, in addition to rejecting custom compilation options.
Texture/sampler source arguments remain explicitly rejected with an unsupported error.
`window-test` exercises MTKView resizing and closes after three size checks.
`window` remains open until closed. The client additionally tests an NSView
subclass requesting its backing layer before super's initializer, independently
of MTKView. That pinned the opacity/geometry initialization bug which caused
the first window to be black; the fix belongs in NSView rather than MetalKit.

Capture only the demo window with:

```sh
magick import -window 'Darling Metal - Render verification' \
  build/metal-baseline/results/window.png
```

## Shapes and animation

```sh
python3 tools/metal-baseline/run-render.py shapes-offscreen \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py shapes-window-test \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py shapes-window \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

`shapes-offscreen` writes `shapes-0.ppm` through `shapes-3.ppm`, one for each
fixed timestamp. `scene.hpp` builds the meshes: two triangles for a square,
96 triangles for a disk, and 192 triangles for the ring. Its inner-radius
parameter is 0.72 of the outer radius. `shapes.metal` applies per-object
transform/color uniforms and passes the color to the fragment shader. Time is
measured with CACurrentMediaTime rather than by counting frames. Source is
compiled once, and the static geometry buffers are created once.

The geometry buffer is bound at Metal index 3 and each draw's uniform bytes at
index 7. These deliberately differ from the compiler's address-table members
0 and 1. The source-library adapter preserves that distinction and orders
addresses by the reflection's member field. This is general buffer handling;
the framework does not know which shapes the client draws.

Pixel validation uses analytic rotated squares, circles and annuli, separately
from the mesh construction. A 1.1-pixel edge band is excluded to account for
tessellation and rasterization boundaries; over 98% of each frame remains
checked. The ring's center must stay background-colored. A blank-frame
negative control must fail, and successive timestamps must produce different
images. The original triangle/clear test still passes after enabling buffers.

`shapes-window-test` checks that frames continue across 900x560, 900x600 and
640x420 sizes and then closes the window. `shapes-window` stays open. Capture
that window with:

```sh
magick import -window 'Darling Metal - Shapes in motion' \
  build/metal-baseline/results/shapes-window.png
```

## Source compilation and current limits

There are two distinct shader paths in the current source:

1. Existing Metal library-loading methods take `.metallib` data and delegate to
   Indium/Iridium. The existing `store-reference` check exercises that backend
   path and verifies a compute result.
2. `mslc` produces SPIR-V plus reflection, which the native Indium API accepts.
   Our two new fixtures verify that path. These bytes are not `.metallib` files.

Metal now implements `newLibraryWithSource:options:error:` through the optional
mslc C library. Metal reads the compiler's version-2 reflection and calls Indium
through its existing interface. The compiler is statically linked with hidden
symbols, and its license is installed with the local build.

The bridge supports vertex/fragment/compute entry points, buffer arguments and
nil compile options. Custom options, texture/sampler resources, embedded samplers and
libraries without entry points return MTLLibraryErrorUnsupported (the compiler
may reject unsupported source earlier with MTLLibraryErrorCompileFailure).
Compilation errors return nil with an NSError when requested. Passing `.spv`
bytes to `newLibraryWithData:error:` is not a supported shortcut: that API still
takes `.metallib`. No undocumented public symbols or application checks were added.

## Provenance

- New fixtures and the test client were written independently for this task.
- Interface contracts: public [Metal documentation](https://developer.apple.com/documentation/metal)
  and [Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf).
- NSView opacity and resize checks follow the documented [alphaValue default](https://developer.apple.com/documentation/appkit/nsview/alphavalue)
  and [MTKView autoResizeDrawable](https://developer.apple.com/documentation/metalkit/mtkview/autoresizedrawable).
- Vertex buffer/byte binding follows the public [setVertexBuffer contract](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setvertexbuffer(_:offset:index:))
  and [setVertexBytes contract](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setvertexbytes(_:length:index:)).
- The server's build with OpenSSL 4 was repaired using const pointers and public
  ASN1_STRING accessors; its existing code-signing tests passed with UBSan.
  Sources: local OpenSSL headers and [OpenSSL ASN1_STRING documentation](https://docs.openssl.org/master/man3/ASN1_STRING_length/).
- Backend interfaces and existing tests: the local Indium checkout at
  `15e3a7ba071f2ffc4df542a6e7c76783fd350441` (ISC license).
- External build tool: [cristim/mslc](https://github.com/cristim/mslc) at
  `6964bb3984e26de95bbca89b08f305a6c4ff3317` (MIT license), used without copying
  its implementation into these files.
- Metal submodule: `51bc1937a0cd6472458d084dfe3ba3ca3b4ea3a4`.
- No restricted Apple source, proprietary disassembly, or application-specific
  workaround informed these new files. CoreCrypto was not inspected or changed.
