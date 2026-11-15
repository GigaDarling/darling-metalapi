# DOOM / Darling Metal 0.5.0

Route: compile the open-source DoomGeneric engine as a Mach-O application, with
an independently written AppKit/Metal frontend and AudioQueue sound module.
The engine is an external pinned build dependency, not a reimplementation of
Apple software. No Apple binaries or restricted source inform this port.

- Engine: https://github.com/ozkl/doomgeneric at
  `e257a09527062bfb986b6e5e0780839b6cbd5b71`, GPL-2.0-or-later (per source notices).
- Source checkout: `build/metal-baseline/vendor/doomgeneric`, ignored build data.
- WAD and saves: separate ignored `build/metal-baseline/v050/data` folder.
- Render path: Doom software framebuffer → MTLTexture → full-screen triangle →
  MTKView/CAMetalLayer → Darling/Indium/Vulkan.
- Input: AppKit keyDown/keyUp/flagsChanged; held keys released on loss of focus.
- Audio: 16-channel DMX effect mixer → AudioQueue → AudioUnit → CoreAudio → PulseAudio.
- API sources: public Metal/MetalKit/AppKit headers; Apple AudioQueueNewOutput
  documentation https://developer.apple.com/documentation/audiotoolbox/audioqueuenewoutput(_:_:_:_:_:_:_:)
- No WAD data, commercial game data, or original proprietary executables are
  part of the source project. Music backend is not implemented yet.

Verified: Mach-O build, visible Intel Metal E1M1 framebuffer, user-confirmed
keyboard gameplay and sound effects, sanitizer-backed DMX mixer and key-state
tests. WAD downloader verified in a new folder. Xvfb/lavapipe cannot present the
external Metal drawable on the tested software path, so it is not the graphics
verification oracle. No changes to existing Metal/AppKit/CoreAudio code were
required for this application.
