# DOOM on Darling Metal — 0.5.0

A source-built DoomGeneric application running **inside Darling**. The original
software renderer produces the Doom framebuffer; our new frontend uploads it to
a Metal texture and draws it through MTKView, Indium and Vulkan. This is not a
hardware-accelerated rewrite of Doom's world renderer and not a native Linux
Doom process displayed in another application's window.

## Play

From the focused `darling-metalapi` source repository after `prepare.py` and
`build.py`:

```sh
python3 demo/doom/get-shareware.py --output build/doom-data
python3 run.py doom-window \
  --darling-prefix work/darling/build/metal-baseline/prefix \
  --demo work/darling/build/metal-baseline/darling/src/tools/doom/doom-metal.app/Contents/MacOS/doom-metal \
  --wad build/doom-data/doom1.wad \
  --icd /usr/share/vulkan/icd.d/intel_icd.json
```

For the binary overlay, the downloader is `source/demo/doom/get-shareware.py`.
Use the same launch command without `--demo`: it defaults to the packaged `bin/doom-metal.app/Contents/MacOS/doom-metal`.
`--engine-args -warp 1 1` (last option) starts E1M1 immediately.

The downloader verifies the SHA-256 of the original shareware ZIP and the
unmodified `DOOM1.WAD`. It retains the original archive and accompanying README
and help notices. It does **not** execute the original DOS installer. WAD data
is downloaded separately and is not in this repository or binary overlay.
You may also provide an IWAD you are entitled to use.

Configurations and saved games persist in
`~/.local/share/darling-metalapi/doom`, independently of the temporary Darling
prefix. Override this with `--state-dir /path/to/doom-state`. F2 saves, F3 loads;
the original Doom save-slot menu is used. Back up that folder before removing it.

| Keys | Action |
| --- | --- |
| W / S or Up / Down | Forward / backward |
| A / D | Strafe left / right |
| Left / Right, Q | Turn (Q turns left) |
| Ctrl, F, left mouse button | Fire |
| Space / E | Use a door or switch |
| Shift | Run |
| 1–7 | Select an available weapon |
| Tab | Automap |
| Esc / Enter | Menu / confirm |
| F2 / F3 | Save / load |

Letters retain their text meaning in menus, including save names. Auto-repeat
does not produce stuck keys. Aliased controls can be held together; losing
window focus releases held controls.

## Audio and rendering

Digital sound effects use an independently written 16-channel stereo DMX PCM
mixer, resampled to 44.1 kHz. Audio goes through the public AudioQueue interface,
then Darling's AudioUnit/CoreAudio/PulseAudio backend. A running PipeWire-Pulse
or PulseAudio server is required. MIDI/OPL **music is not implemented**; the
launcher supplies `-nomusic`.

The 320×200 framebuffer uses nearest sampling and a 4:3 viewport with letterbox
bars when resized. OpenGL (the compositor) and Vulkan (Metal) must use the same
GPU. Intel desktop rendering is verified. Xvfb/lavapipe presentation is not
supported by this demo's tested path; unit tests do not need a desktop.

## Build dependency and provenance

`fetch-engine.py` obtains the separate, clean DoomGeneric checkout at
`e257a09527062bfb986b6e5e0780839b6cbd5b71` from
https://github.com/ozkl/doomgeneric. The engine is GPL-2.0-or-later under its
source notices; this frontend and tools are GPL-3.0-or-later. Full upstream
notices are retained. `build.py` fetches this dependency automatically.

The engine's SDL sound-header include is removed in a generated build copy of
its sound dispatcher; its sound API is implemented by our AudioQueue module.
The engine's existing portable graphics/input entry points are implemented by
our AppKit/Metal frontend. No Apple implementation source or binaries were
used. Sources: public Metal/MetalKit/AppKit and AudioQueue contracts, the licensed
DoomGeneric module interfaces, and the documented DMX sound-lump format.

Shareware source: the original id Software FTP distribution mirrored at
https://ftp.gwdg.de/pub/misc/ftp.idsoftware.com/idstuff/doom/doom19s.zip

Archive SHA-256: `cacf0142b31ca1af00796b4a0339e07992ac5f21bc3f81e7532fe1b5e1b486e6`.
WAD SHA-256: `1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771`.

## Checks

```sh
c++ -std=c++17 -fsanitize=address,undefined mixer-test.cpp -o /tmp/doom-mixer-test
ASAN_OPTIONS=detect_leaks=0 /tmp/doom-mixer-test
c++ -std=c++17 -fsanitize=address,undefined input-test.cpp -o /tmp/doom-input-test
ASAN_OPTIONS=detect_leaks=0 /tmp/doom-input-test
```

These cover malformed/truncated DMX data, channel mixing and completion, stereo
separation, resampling, saturation, key repeat, aliases, menu transitions and
focus loss. Leak detection is disabled only for compatibility with sandboxed
test execution; address and undefined-behavior checks remain enabled.

Manual integration: actual E1M1 graphics inspected in the Intel desktop window;
movement, firing, doors and pickup sounds confirmed by the user. The software
Doom engine is unchanged, and its sound and video modules run in the same
Mach-O application.

AI assistance: OpenAI Codex helped implement this frontend, build integration
and tests. DoomGeneric and the upstream compatibility projects retain their
separate authorship and license notices.
