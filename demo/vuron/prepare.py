#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare narrowly scoped, reproducible platform adaptations of MIT Vuron."""
from pathlib import Path
import argparse
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
def replace(text,old,new):
    if text.count(old)!=1: raise ValueError('Upstream source changed: '+old[:70])
    return text.replace(old,new)
renderer=(a.source/'src/renderer/MetalRenderer.mm').read_text()
renderer=replace(renderer,'<Appkit/NSWindow.h>','<AppKit/NSWindow.h>')
(a.output/'MetalRenderer.mm').write_text(renderer)
window=(a.source/'src/platform/mac/MacWindow.mm').read_text()
window=replace(window,'#include "MacWindow.h"','#include "platform/mac/MacWindow.h"')
window=replace(window,'#include "../../renderer/MetalRenderer.h"','#include "renderer/MetalRenderer.h"')
window=replace(window,'#include "../../core/Memory.h"','#include "core/Memory.h"')
window=replace(window,'namespace vuron\n{','''namespace vuron
{
    // Windowed-game usability: capture only on click; Escape/focus loss release it.
    static bool mouseCaptured = false;
    static void captureMouse(bool capture) {
        if (mouseCaptured == capture) return;
        CGAssociateMouseAndMouseCursorPosition(!capture);
        if (capture) [NSCursor hide]; else [NSCursor unhide];
        mouseCaptured = capture;
    }
''')
window=replace(window,'[window setTitle:@"Vuron Engine"];','''[window setTitle:@"Darling Metal 0.7.0 - Vuron"];
      [window setAcceptsMouseMovedEvents:YES];
      [window center];''')
window=replace(window,'         exit(0);\n       }];','         captureMouse(false);\n         exit(0);\n       }];')
window=replace(window,'      CGAssociateMouseAndMouseCursorPosition(NO);\n      [NSCursor hide];','''      if (![(NSWindow*)m_windowHandle isKeyWindow]) {
          captureMouse(false);
          for (char key : {'w', 'a', 's', 'd', ' ', 'r', 'g', 'e', 'C'})
              m_renderer->setKeyState(key, false);
          m_renderer->setMouseState(false);
          m_renderer->setRightMouseState(false);
      }''')
window=replace(window,'            // Convert the keystroke into a string','''            if (event.keyCode == 53) { captureMouse(false); continue; }
            // Convert the keystroke into a string''')
window=replace(window,'            m_renderer->setMouseState(true); // Left button pressed','''            if (!mouseCaptured) { captureMouse(true); continue; }
            m_renderer->setMouseState(true); // Left button pressed''')
window=replace(window,'            m_renderer->addMouseDelta(dx, dy);','            if (mouseCaptured) m_renderer->addMouseDelta(dx, dy);')
(a.output/'MacWindow.mm').write_text(window)
