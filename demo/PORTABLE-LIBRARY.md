# Darling SPIR-V library, version 1

This is an independently designed, open format for libraries produced by
`compile-library.py` and mslc. It is **not Apple's AIR/metallib encoding** and
does not claim to load arbitrary shader libraries built by Apple's compiler.
The filename `default.metallib` follows Metal's documented bundle resource
convention; the bytes belong to Darling's own toolchain.

| Offset | Size | Value |
| --- | --- | --- |
| 0 | 8 bytes | ASCII `DMSLSPV` followed by NUL |
| 8 | uint32 LE | Version, 1 |
| 12 | uint32 LE | SPIR-V byte count, at least 20 and divisible by 4 |
| 16 | uint32 LE | Nonzero UTF-8 reflection JSON byte count |
| 20 | uint32 LE | Reserved, zero |
| 24 | variable | SPIR-V words, followed immediately by mslc reflection v2 |

The file has no trailing bytes. Producer and consumer validate exact lengths;
all integer fields are little-endian. The loader copies words to aligned storage
before entering Indium and uses the same reflection adapter as source libraries.
The loader also bounds-checks instruction framing and matches entry-point names
and execution stages against reflection before import. This is not full SPIR-V
semantic validation.
Indium retains responsibility for creating the Vulkan shader module and binding
resources. No higher framework reaches into Vulkan directly.

`newDefaultLibrary`, `newDefaultLibraryWithBundle:error:`, `newLibraryWithURL:error:`
and `newLibraryWithData:error:` use this same path. Unknown magic retains the
existing Indium library path. Unsupported container versions return
`MTLLibraryErrorUnsupported`; damaged headers, invalid reflection and rejected
SPIR-V return `MTLLibraryErrorCompileFailure`. A nil NSError output is supported.
No public Apple API symbols are added; loader helpers have hidden visibility.

Offline compilation:

```sh
python3 compile-library.py shader.metal --mslc /path/to/mslc \
  -I /path/to/headers -o MyApp.app/Contents/Resources/default.metallib
```

The compiler runs `spirv-val` through mslc's `--validate` option. The runtime
imports supported, compiler-produced Vulkan SPIR-V using the existing Indium
contract; it is not a replacement for the full SPIR-V validator. Runtime source
compilation can be disabled while loading these offline libraries.

Provenance: public Metal library/bundle APIs, the published SPIR-V specification,
licensed mslc reflection v2 and Indium's public SPIR-V import interface. No Apple
binary was inspected to invent this format.
