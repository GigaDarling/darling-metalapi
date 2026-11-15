# Official Apple sample on Darling

This is Apple's **Synchronizing CPU and GPU Work**, downloaded directly from
https://docs-assets.developer.apple.com/published/a2ec04f3244c/SynchronizingCPUAndGPUWork.zip
and described at https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work.
The archive's SHA-256 is recorded in `upstream.json`. The sample license is MIT;
Apple's copyright and full license are preserved in `upstream/LICENSE.txt`.

All six `upstream/Renderer/` files are byte-for-byte copies from that archive.
The 50 triangles, sine-wave animation, three frame buffers, semaphore, pipeline
and completion-handler code are Apple's, not a re-creation made to resemble it.
The shader and shared vertex header are compiled unchanged by mslc.

`main.mm`, `validation.hpp`, `library-tests.mm`, Info.plist and the CMake build
are independently authored integration and test code. The Xcode/storyboard app
shell is replaced by a programmatic AppKit window. At build time only, Clang
module imports in generated Objective-C files are replaced with equivalent
`#import <MetalKit/MetalKit.h>` headers for Darling's SDK. Renderer logic remains
unchanged. The generated host files use Darling's SIMD headers.

Xcode's offline shader build is replaced by `compile-library.py`, producing
Darling SPIR-V plus reflection in the app bundle. Apple's renderer still calls
`newDefaultLibrary` normally. See [the format description](../PORTABLE-LIBRARY.md).
This is a source build of an official example, not execution of a prebuilt Apple
application or AIR library, and not a claim of complete SDK compatibility.

From the local Darling repository:

```sh
python3 tools/metal-baseline/run-render.py apple-window \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py apple-library-test \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
python3 tools/metal-baseline/run-render.py apple-window-test \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

The normal window animates continuously until closed. Tests use a separate
"Verification" window and close it after 180 frames. Test-only readable drawables
are copied into shared CPU buffers with a blit encoder and padded row strides.
An analytic host reference checks color, occlusion order and sine-wave geometry
at frames 1, 59, 119 and 179, over 1000x600, 800x500 and 640x420 drawables.
A deliberately wrong phase must fail. The test queue barrier accesses the openly
licensed sample object's own `_commandQueue` via Objective-C runtime metadata;
no Apple framework implementation or private binary is inspected or modified.
Normal interactive mode has no CPU readback or queue introspection.

Validated on Intel Iris Xe: 442,692 sampled pixels, zero mismatches, 35,522
triangle-interior samples, all four wrong-phase controls reject. Library tests
exercise URL, main/explicit bundle, contiguous and segmented dispatch data,
entry-point metadata and 36 rejection cases, with and without NSError output.
The first unmodified runtime failed at `newDefaultLibrary` with invalid library
magic; the new general format loader fixes that toolchain gap for all callers.

These checks validate the source and binary overlay included in v0.4.0.


## Native AppKit menus and input

The app bootstrap adds NSMenu/NSMenuItem menus: File, Edit, View, Window and
Help (shown in Russian), plus the app menu. Darling's Linux AppKit puts the
menu bar inside the window. No fake menu drawing or backend special cases are
used. The renderer and shader sources remain unchanged.

The click button increments a visible counter. The pause button, View menu,
left click on the Metal view, and Space while the scene is focused share the
same application action. "One frame" pauses and advances exactly once. The
editable text field exercises standard cut/copy/paste/select-all responder
chain actions; menu items leave their target nil for standard Cocoa routing.
Mouse movement/dragging updates local coordinates, and right click opens an
NSMenu context menu. Input lives in the sample app's MTKView subclass.

Public contract sources: https://developer.apple.com/documentation/appkit/nsmenu,
https://developer.apple.com/documentation/appkit/nsresponder/mousedown(with:),
https://developer.apple.com/documentation/appkit/nswindow/acceptsmousemovedevents.
The input changes use the existing open Cocotron AppKit implementation; no
framework fix was needed just to display the standard menus and button.


Menu compatibility fixes are in Cocotron's AppKit/X11 layers: do not cache a
miss from submenu hit testing; ignore temporary keyboard-grab focus notices;
keep the application active during focus transfers between its own windows
(including native child windows). The new owner is activated before the previous
owner is retired. Real departure to another client still deactivates normally.
The separate X11 backend plugin must be rebuilt/installed with AppKit.

A regression reproduces entering through the submenu's border. X11 protocol
checks additionally transfer actual focus from a native child to the popup,
then select an item, open NSAlert, and close it via its OK action. These checks
run on a private Xvfb and only send events to the fixture or its own transient
popup. They do not move the desktop mouse. Example from the Darling root:

```sh
python3 tools/metal-baseline/apple-sync/check-private-x11.py \
  --xvfb /path/to/Xvfb --output build/metal-baseline/results/appkit-input
```

Five private-server cases pass: normal selection, grab/ungrab, internal popup
focus transfer, native alert, and internal focus transfer followed by an alert.
The user confirmed real mouse/menu operation after the internal focus fix,
then reported the remaining one-frame, text-editing and context-menu checks
as working. Full real-input behavior is not inferred from synthetic events alone.
