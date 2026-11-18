# Model viewer — Darling Metal 0.6.0

Flight Helmet is rendered as real indexed 3D geometry by a Mach-O application
inside Darling. Metal performs perspective projection, rasterization, depth
testing and material shading through Indium/Vulkan. The scene has **55,392
vertices, 94,722 triangles, six primitives/materials and 15 textures**.

The model is the CC0 Flight Helmet from the Khronos glTF Sample Assets
repository, converted by Gary Hsu. Original geometry and texture SHA-256 hashes
are pinned in `sample-assets.json`. Original source files are fetched separately;
the binary package includes a prepared model and this notice. See
[ASSET-NOTICE.md](ASSET-NOTICE.md).

## Run

Normal source builds (`build.py`) fetch, verify and prepare the sample. Then:

```sh
python3 run.py model-window \
  --darling-prefix work/darling/build/metal-baseline/prefix \
  --demo work/darling/build/metal-baseline/darling/src/tools/model/model-viewer.app/Contents/MacOS/model-viewer \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

For the binary package, omit `--demo` to use the included app and model.
OpenGL (the compositor) and Vulkan must select the same GPU. The Intel ICD in
the example should be replaced when running on another GPU.

| Input | Action |
| --- | --- |
| Drag with the left mouse button | Rotate the view; stop automatic rotation |
| Mouse wheel, + / − | Zoom |
| Arrow keys | Rotate the view |
| Space | Toggle automatic rotation |
| L | Switch between lit materials and base-color textures |
| N | Show/hide the normal-map view |
| R | Reset view and shading |

## Import another static model

```sh
python3 demo/model/prepare-model.py scene.gltf -o build/scene.dmodel --texture-size 1024
python3 run.py model-window --darling-prefix /path/to/darling-prefix \
  --demo /path/to/model-viewer --model build/scene.dmodel
```

The host-side importer reads `.gltf` and GLB, resolves local/data-URI buffers,
decodes interleaved accessors and unsigned indices, flattens the active scene's
node transforms, applies inverse-transpose normals, and produces uint32 indexed
geometry. Missing normals become flat face normals; missing tangents are
generated from positions and UVs. The scene is centered and fitted uniformly.
Images become bounded RGBA textures. The guest reads the documented model pack;
it does not rely on a native Linux renderer or a pre-rendered image.

Supported input is static, uncompressed triangle geometry with opaque
metallic/roughness materials and `TEXCOORD_0`. Skins, morph targets, sparse
accessors, compression, texture transforms, transparent materials and required
extensions are rejected with an error. Animation channels are not evaluated;
nodes are shown in their base pose. Optional transmission in the sample uses
its core opaque-material fallback: **glass refraction is not implemented**.

Materials use base color, tangent-space normals, metallic/roughness, occlusion
and emissive maps. Shading includes direct GGX highlights, studio fill and
ambient light, tone mapping and display gamma. Environment lighting/IBL,
shadows and full glTF material-extension support are not claimed. Sample images
are reduced to at most 1024×1024 for the default build; the original pinned
images remain unmodified in the download cache.

## Verification

```sh
python3 demo/model/test-import.py
c++ -std=c++17 -fsanitize=address,undefined demo/model/format-test.cpp -o /tmp/model-format-test
ASAN_OPTIONS=detect_leaks=0 /tmp/model-format-test /path/to/FlightHelmet.dmodel
python3 run.py model-offscreen --darling-prefix /path/to/darling-prefix \
  --demo /path/to/model-viewer --output results/model.ppm \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

Synthetic glTF tests cover interleaving, uint16 indices, missing normals, node
instancing and transforms, GLB, quaternion rotation, inverse-transpose normals,
truncated accessors, invalid indices, cycles, directory escapes and unsupported
features. The native model-pack reader is tested with every possible truncation
of a minimal fixture, malformed counts, NaN, bad indices/ranges, material/texture
references and trailing data, with ASan/UBSan.

The offscreen GPU test uses three angles/aspect ratios. It compares stable
material-ID pixels against an independent CPU ray/triangle nearest-hit oracle,
reverses primitive submission to verify depth ordering, and checks rotation and
a blank-image negative control. The textured output is also written to PPM.
Intel Iris Xe and lavapipe pass with zero geometry/depth mismatches. The user
confirmed the real window, rotation, dragging, zoom and pause.

## Model pack v1

All numbers are little-endian. Header: 8 bytes `DMODEL1\0`, then five uint32
counts: vertices, indices, primitives, materials and images. Sections follow:

- Vertex: sixteen float32 values, grouped as position, normal, UV and tangent
  float4s (64 bytes); position `w` is 1, tangent `w` carries handedness.
- Indices: uint32, referencing the vertex section.
- Primitive: four uint32 values: first index, count, material and zero reserved.
  Primitive ranges partition the index section contiguously.
- Material: twelve float32 values (base color, metallic/roughness/normal-scale/
  occlusion-strength, emissive/reserved), then five uint32 image references
  (base color, normal, metallic/roughness, occlusion, emissive). `0xffffffff`
  selects the appropriate neutral texture.
- Image: uint32 width/height, followed by width×height×4 RGBA8 bytes.

The reader bounds file size, counts, texture dimensions and every section;
rejects non-finite values and invalid references, and refuses trailing data.

Provenance: public Metal/MetalKit/AppKit contracts, the
[glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
and the CC0 sample. Importer, model format, renderer, shaders and tests are
independently authored GPL-3.0-or-later code, prepared with assistance from
OpenAI Codex. No restricted Apple source or binary analysis was used. Host
image conversion uses Pillow (MIT-CMU), an external build dependency.
