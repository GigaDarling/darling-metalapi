// SPDX-License-Identifier: GPL-3.0-or-later
#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>
#import "renderer.h"
#include <algorithm>
#include <cstdio>
#include <cstring>

static ModelRenderer* renderer;
static bool automatic=true;
static const char* modelPath=nullptr;
@interface ModelView : MTKView<MTKViewDelegate>
@end
@implementation ModelView
- (BOOL)acceptsFirstResponder {return YES;}
- (BOOL)acceptsFirstMouse:(NSEvent*)event {return YES;}
- (void)drawInMTKView:(MTKView*)view {
    id<CAMetalDrawable> drawable=self.currentDrawable;if (!drawable) return;
    id<MTLCommandBuffer> command=[[renderer queue] commandBuffer];
    [renderer encode:command texture:drawable.texture reverse:NO];
    [command presentDrawable:drawable];[command commit];[command waitUntilCompleted];
    if (command.error) {std::fprintf(stderr,"Model rendering failed: %s\n",command.error.description.UTF8String);[NSApp stop:nil];}
}
- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {}
- (void)mouseDown:(NSEvent*)event {[self.window makeFirstResponder:self];}
- (void)mouseDragged:(NSEvent*)event {
    automatic=false;renderer.yaw+=event.deltaX*.008f;
    renderer.pitch=std::clamp(renderer.pitch+float(event.deltaY)*.008f,-1.3f,1.3f);
}
- (void)scrollWheel:(NSEvent*)event {renderer.distance=std::clamp(renderer.distance+float(event.scrollingDeltaY)*.10f,2.0f,12.0f);}
- (void)keyDown:(NSEvent*)event {
    switch (event.keyCode) {
        case 49:automatic=!automatic;return;
        case 15:renderer.yaw=.15f;renderer.pitch=.12f;renderer.distance=3.2f;renderer.mode=0;return;
        case 37:renderer.mode=renderer.mode==1?0:1;return;
        case 45:renderer.mode=renderer.mode==2?0:2;return;
        case 123:automatic=false;renderer.yaw-=.12f;return;
        case 124:automatic=false;renderer.yaw+=.12f;return;
        case 125:automatic=false;renderer.pitch=std::max(-1.3f,renderer.pitch-.08f);return;
        case 126:automatic=false;renderer.pitch=std::min(1.3f,renderer.pitch+.08f);return;
        case 24:renderer.distance=std::max(2.0f,renderer.distance-.2f);return;
        case 27:renderer.distance=std::min(12.0f,renderer.distance+.2f);return;
    }
    [super keyDown:event];
}
@end
@interface ModelApplication : NSObject<NSApplicationDelegate,NSWindowDelegate> {
    NSWindow* _window;ModelView* _view;NSTimer* _timer;NSTextField* _status;
    unsigned _frames;NSTimeInterval _last;
}
@end
@implementation ModelApplication
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if (!device) {std::fprintf(stderr,"No Metal device\n");std::exit(1);}
    renderer=[[ModelRenderer alloc] initWithDevice:device path:modelPath];
    _window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1100,810) styleMask:NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
    _window.title=@"Darling Metal 0.6.0 - Flight Helmet";_window.releasedWhenClosed=NO;_window.delegate=self;
    _view=[[ModelView alloc] initWithFrame:NSMakeRect(0,42,1100,768) device:device];
    _view.paused=YES;_view.enableSetNeedsDisplay=NO;_view.delegate=_view;
    _view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [_window.contentView addSubview:_view];
    _status=[[NSTextField alloc] initWithFrame:NSMakeRect(12,9,1076,23)];
    _status.editable=NO;_status.selectable=NO;_status.bezeled=NO;_status.drawsBackground=NO;
    _status.autoresizingMask=NSViewWidthSizable;[_window.contentView addSubview:_status];
    _status.stringValue=[NSString stringWithFormat:@"%lu triangles | %lu materials | Drag: rotate | Wheel: zoom | Space: auto | L: lighting | N: normals | R: reset",(unsigned long)renderer.triangles,(unsigned long)renderer.materials];
    [_window center];[_window makeKeyAndOrderFront:nil];[_window makeFirstResponder:_view];[NSApp activateIgnoringOtherApps:YES];
    _last=[NSDate timeIntervalSinceReferenceDate];
    _timer=[NSTimer scheduledTimerWithTimeInterval:1.0/60 target:self selector:@selector(frame:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)frame:(NSTimer*)timer {
    NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    if (automatic) renderer.yaw+=float(std::min(now-_last,.1))*.32f;
    _last=now;[_view draw];++_frames;
}
- (void)windowWillClose:(NSNotification*)notification {[_timer invalidate];[NSApp stop:nil];}
@end
int main(int argc,char** argv) {
    @autoreleasepool {
        std::setbuf(stdout,nullptr);const char* output=nullptr;
        for (int i=1;i<argc;++i) {
            if (!std::strcmp(argv[i],"--model") && i+1<argc) modelPath=argv[++i];
            else if (!std::strcmp(argv[i],"--offscreen") && i+1<argc) output=argv[++i];
            else {std::fprintf(stderr,"Usage: model-viewer [--model file.dmodel] [--offscreen image.ppm]\n");return 2;}
        }
        NSString* bundled=[[NSBundle mainBundle] pathForResource:@"FlightHelmet" ofType:@"dmodel"];
        if (!modelPath) modelPath=bundled.fileSystemRepresentation;
        if (!modelPath) {std::fprintf(stderr,"No model pack: run prepare-model.py or pass --model\n");return 1;}
        try {
            if (output) {
                id<MTLDevice> device=MTLCreateSystemDefaultDevice();
                if (!device) {std::fprintf(stderr,"No Metal device\n");return 1;}
                renderer=[[ModelRenderer alloc] initWithDevice:device path:modelPath];
                [renderer verifyOffscreen:output];return 0;
            }
            [NSApplication sharedApplication];ModelApplication* application=[ModelApplication new];
            NSApp.delegate=application;[NSApp run];
        } catch (const std::exception& error) {std::fprintf(stderr,"Model viewer: %s\n",error.what());return 1;}
    }
    return 0;
}
