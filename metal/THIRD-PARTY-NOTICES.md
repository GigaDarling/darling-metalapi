# Optional source compiler

When `MSLC_SOURCE_DIR` is set, Metal links the mslc compiler statically.

- Source: https://github.com/cristim/mslc
- Validated revision: `6964bb3984e26de95bbca89b08f305a6c4ff3317`
- License: MIT
- Copyright (c) 2026 Cristian Magherusan-Stanciu
- The checkout retains its license and notices. The build installs its complete
  `LICENSE` as `share/licenses/darling-metal/mslc-LICENSE`.

The integration and reflection adapter were independently written against the
compiler's C API and the public Metal contract. No compiler implementation was
copied into Metal's source files. No restricted Apple source was used.
