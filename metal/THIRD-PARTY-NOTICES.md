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

For darling-metalapi v0.3.0 this compiler base is extended by the MIT
`patches/mslc-read-write.patch` shipped in the focused source release. The patch
adds independently authored access::read_write lowering and contract probes;
see https://github.com/cristim/mslc/issues/96 for the upstream tracking issue.
