// SPDX-License-Identifier: GPL-3.0-or-later
#import <AppKit/NSEvent.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreGraphics/CGRemoteOperation.h>
#include <cstdio>
static_assert(NSEventMaskAny == ~0ULL, "all event mask covers the mask type");
static_assert(NSEventModifierFlagCommand == NSCommandKeyMask, "command alias");
static_assert(NSEventModifierFlagShift == NSShiftKeyMask, "shift alias");
static_assert(NSEventModifierFlagControl == NSControlKeyMask, "control alias");
static_assert(NSEventModifierFlagOption == NSAlternateKeyMask, "option alias");
// Importing CAMetalLayer must expose the drawable protocol's API and inheritance.
static id<MTLTexture> drawableTexture(id<CAMetalDrawable> drawable) {return drawable.texture;}
static id<MTLDrawable> baseDrawable(id<CAMetalDrawable> drawable) {return drawable;}
// Taking its address verifies the C linkage without changing mouse state.
CGError (*volatile mouseAssociation)(boolean_t) = &CGAssociateMouseAndMouseCursorPosition;
int main() {if (!mouseAssociation) return 1;std::puts("PASS AppKit aliases, CAMetalDrawable declaration and CoreGraphics C linkage");return 0;}
