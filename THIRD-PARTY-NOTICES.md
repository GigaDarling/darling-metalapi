# Sources, credits and licenses

This project builds on Darling and darling-metal. It does not claim authorship
of their existing Metal API, Vulkan backend or window system.
Exact upstream revisions are recorded in `upstream.json`.

| Component | Source | License / included notice |
| --- | --- | --- |
| Darling integration and independently authored demo/tools | https://github.com/GigaDarling/darling-metalapi | GPL-3.0-or-later, `LICENSE` |
| Metal and MetalKit implementation and public headers | https://github.com/darlinghq/darling-metal | Per-file MPL-2.0 notices; `metal/LICENSES/` |
| Indium / Iridium | https://github.com/darlinghq/indium | 0BSD, `licenses/indium-LICENSE` |
| mslc, statically linked into Metal when enabled | https://github.com/cristim/mslc | MIT, `licenses/mslc-LICENSE` |
| Cocotron AppKit, including the NSView initialization fix | https://github.com/darlinghq/darling-cocotron | MIT, `licenses/cocotron-LICENSE` |

The `metal/` source snapshot is intentionally retained with its own notices and
directory structure. It is based on upstream commit
`643f57199d7b9eb5246a79e7568ffe6c7ad9e723`; source-library compilation,
reflection adaptation and build integration are local changes. The separate
`metal/THIRD-PARTY-NOTICES.md` describes the optional mslc integration.

The NSView and darlingserver patches retain the upstream context needed to
apply them. They are independently authored modifications. The OpenSSL patch
uses public accessors and const-correct types; it changes no cryptographic
primitive or signature-validation policy. The darlingserver executable and
OpenSSL are not distributed in the binary overlay.

The binary overlay contains the compiled GPL demo together with all its source
files and shader sources under `source/demo/`. The source repository provides
the modified MPL-covered Metal sources and pinned backend/compiler submodules.
Host Vulkan, OpenGL, LLVM, libc and the rest of Darling are external dependencies.

Research and implementation used public Metal/NSView contracts, the public mslc
C API and open Indium interfaces. No restricted Apple source, CoreCrypto source,
Apple binary disassembly or decompilation was used. The screenshot and video
show the independently authored demo running in a real Darling window.

For v0.3.0, mslc read/write texture access is extended by the independently
written `patches/mslc-read-write.patch` (including compiler contract probes).
The base is the MIT-licensed revision in upstream.json; the patch does not
claim upstream acceptance. Indium viewport and storage image compatibility
changes are in `patches/indium-compatibility.patch` (0BSD).

Provenance: public Metal Shading Language texture/sampler contracts
(https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf),
public Metal usage flags, the Khronos Vulkan descriptor/storage-image contract
(https://docs.vulkan.org/spec/latest/chapters/descriptorsets.html), and the
licensed mslc/Indium interfaces. No third-party implementation was copied into
the new compiler feature. New upstream Metal files retain their MPL notices;
upstream guest tests are not redistributed in this snapshot.

## Official Apple sample in v0.4.0

`demo/apple-sync/upstream/` contains the MIT-licensed renderer, shader, shared
header, README and documentation images from Apple's official Synchronizing
CPU and GPU Work sample, downloaded from:
https://docs-assets.developer.apple.com/published/a2ec04f3244c/SynchronizingCPUAndGPUWork.zip

SHA-256: `33a12c250263f261ce3816f2d0ff0c410eb0d1b90a3156fde7df3b0aefcdc205`.
Copyright 2026 Apple Inc. Full license: `demo/apple-sync/upstream/LICENSE.txt`.
Unlike restricted Apple platform implementation sources, this sample expressly
permits use, modification and distribution under the included MIT terms. It is
redistributed unchanged with attribution; the independently authored app shell,
format packager and tests are GPL-3.0-or-later. The format loader in Metal is MPL-2.0.
No Apple AIR/metallib implementation, restricted source or binary internals were
used. This is a sample source build through Darling's own offline shader format.

## DOOM application in v0.5.0

DoomGeneric is an external build dependency at
`e257a09527062bfb986b6e5e0780839b6cbd5b71`, from
https://github.com/ozkl/doomgeneric, GPL-2.0-or-later per its source notices.
The original notices and license are retained in the separate engine checkout;
corresponding engine sources accompany the binary application under
`source/doomgeneric`. Frontend, mixer and build integration are independently
written GPL-3.0-or-later code under `demo/doom` (`source/demo/doom` in the overlay).
The generated dispatcher removes only an unused SDL_mixer include, to select
our AudioQueue sound module. No Doom engine implementation is claimed as ours.

The shareware IWAD is separately copyrighted game data, not GPL source. It is
not shipped in this source repository or binary overlay. The optional downloader
fetches and verifies the original shareware distribution from an id FTP mirror,
retaining the archive and its original accompanying notices locally. No retail
WAD or proprietary Doom executable is needed or redistributed.

Provenance: publicly documented Metal/MetalKit/AppKit/AudioQueue interfaces,
licensed DoomGeneric module contracts and the DMX PCM lump format. No Apple
binary analysis or restricted material was used. The DOOM screenshot records
actual gameplay through Darling Metal on an Intel GPU. Music is not supported.

## Complex model viewer in v0.6.0

Flight Helmet is a CC0-1.0 sample from KhronosGroup/glTF-Sample-Assets, pinned to
`4995a638c96dbc94376d3d6164e70fee3ac7f7a2`. Upstream credits Gary Hsu for conversion
from Maya and identifies the asset as public domain, 2018. Source, exact hashes
and credit are recorded in `demo/model/sample-assets.json` and
`demo/model/ASSET-NOTICE.md`. The application bundle includes a prepared copy:
flattened/scaled geometry and decoded/resized RGBA images. Original downloads
are not overwritten. The original glTF and textures are fetched independently
for source builds; their license is separate from the GPL program.

The model importer, bounded pack format, renderer, shader and tests are
independently authored GPL-3.0-or-later code. Host-side image conversion uses
Pillow (MIT-CMU), not bundled Python implementation code. No new guest library
or framework implementation is introduced. Provenance: public Metal/MetalKit/
AppKit contracts, the Khronos glTF 2.0 specification, and the licensed sample.
No Apple binary inspection or restricted source was used. Development was
assisted by OpenAI Codex. Source and binary distributions retain this notice.
