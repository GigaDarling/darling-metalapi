# Sources, credits and licenses

This project builds on Darling and darling-metal. It does not claim authorship
of their existing Metal API, Vulkan backend or window system.
Exact upstream revisions are recorded in `upstream.json`.

| Component | Source | License / included notice |
| --- | --- | --- |
| Darling integration and independently authored demo/tools | https://github.com/japNslow/darling-metalapi | GPL-3.0-or-later, `LICENSE` |
| Metal and MetalKit implementation and public headers | https://github.com/darlinghq/darling-metal | Per-file MPL-2.0 notices; `metal/LICENSES/` |
| Indium / Iridium | https://github.com/darlinghq/indium | 0BSD, `licenses/indium-LICENSE` |
| mslc, statically linked into Metal when enabled | https://github.com/cristim/mslc | MIT, `licenses/mslc-LICENSE` |
| Cocotron AppKit, including the NSView initialization fix | https://github.com/darlinghq/darling-cocotron | MIT, `licenses/cocotron-LICENSE` |

The `metal/` source snapshot is intentionally retained with its own notices and
directory structure. It is based on upstream commit
`51bc1937a0cd6472458d084dfe3ba3ca3b4ea3a4`; source-library compilation,
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
