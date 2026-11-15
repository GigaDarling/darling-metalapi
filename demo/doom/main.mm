// SPDX-License-Identifier: GPL-3.0-or-later
#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>
#include "input.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <time.h>
extern "C" {
#include "doomgeneric.h"
#include "doomkeys.h"
#include "i_system.h"
#include "doomstat.h"
}

namespace {
DoomInput::State input;
bool running=true;
bool applicationReady=false;
bool engineExited=false;
void requireDoom(bool value,const char* message) {
    if (!value) { std::fprintf(stderr,"DOOM Metal: %s\n",message);std::exit(1); }
}
void releaseKeys() { input.releaseAll(); }
void engineQuit() { engineExited=true;running=false;[NSApp stop:nil]; }
unsigned char translate(NSEvent* event) {
    // AppKit virtual key codes remain stable when the text input layout changes.
    // Keep letters as text in menus (notably while naming a saved game).
    if (!menuactive && gamestate==GS_LEVEL) switch (event.keyCode) {
        case 0: return KEY_STRAFE_L; case 1: return KEY_DOWNARROW;
        case 2: return KEY_STRAFE_R; case 13: return KEY_UPARROW;
        case 12: return KEY_LEFTARROW; case 14: return KEY_USE;
        case 3: return KEY_FIRE;
    }
    switch (event.keyCode) {
        case 49: return KEY_USE; case 36: return KEY_ENTER;
        case 53: return KEY_ESCAPE; case 48: return KEY_TAB;
        case 123: return KEY_LEFTARROW; case 124: return KEY_RIGHTARROW;
        case 125: return KEY_DOWNARROW; case 126: return KEY_UPARROW;
        case 51: return KEY_BACKSPACE;
        case 122: return KEY_F1; case 120: return KEY_F2;
        case 99: return KEY_F3; case 118: return KEY_F4;
        case 96: return KEY_F5; case 97: return KEY_F6;
        case 98: return KEY_F7; case 100: return KEY_F8;
        case 101: return KEY_F9; case 109: return KEY_F10;
        case 103: return KEY_F11; case 111: return KEY_F12;
    }
    NSString* text=event.charactersIgnoringModifiers;
    if (!text.length) return 0;
    unichar c=[text characterAtIndex:0];
    if (c>='A' && c<='Z') c+='a'-'A';
    return c<128?c:0;
}
}

@interface DoomView : MTKView<MTKViewDelegate> {
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLTexture> _image;
}
- (void)presentFrame;
@end
@implementation DoomView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)mouseDown:(NSEvent*)event { [self.window makeFirstResponder:self];input.set(256,KEY_FIRE,true); }
- (void)mouseUp:(NSEvent*)event { input.set(256,KEY_FIRE,false); }
- (void)keyDown:(NSEvent*)event { input.set(event.keyCode,translate(event),true); }
- (void)keyUp:(NSEvent*)event { input.set(event.keyCode,0,false); }
- (void)flagsChanged:(NSEvent*)event {
    input.set(257,KEY_FIRE,(event.modifierFlags&NSControlKeyMask)!=0);
    input.set(258,KEY_RSHIFT,(event.modifierFlags&NSShiftKeyMask)!=0);
    input.set(259,KEY_RALT,(event.modifierFlags&NSAlternateKeyMask)!=0);
}
- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device {
    self=[super initWithFrame:frame device:device];if (!self) return nil;
    self.paused=YES;self.enableSetNeedsDisplay=NO;self.delegate=self;
    self.colorPixelFormat=MTLPixelFormatBGRA8Unorm;
    self.clearColor=MTLClearColorMake(0,0,0,1);
    _queue=[device newCommandQueue];
    NSString* shader=@"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct V { float4 position [[position]]; float2 uv; };\n"
        "vertex V screen_vertex(uint i [[vertex_id]]) {\n"
        "float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};\n"
        "V v; v.position=float4(p[i],0,1);v.uv=float2((p[i].x+1)*0.5,(1-p[i].y)*0.5);return v;}\n"
        "fragment float4 screen_fragment(V v [[stage_in]],texture2d<float> image [[texture(0)]]) {\n"
        "constexpr sampler s(coord::normalized,filter::nearest,address::clamp_to_edge);\n"
        "return float4(image.sample(s,v.uv).rgb,1);}";
    NSError* error=nil;id<MTLLibrary> library=[device newLibraryWithSource:shader options:nil error:&error];
    if (!library) std::fprintf(stderr,"Metal compiler: %s\n",error.description.UTF8String);
    requireDoom(library!=nil,"shader compilation failed");
    MTLRenderPipelineDescriptor* pipeline=[MTLRenderPipelineDescriptor new];
    pipeline.vertexFunction=[library newFunctionWithName:@"screen_vertex"];
    pipeline.fragmentFunction=[library newFunctionWithName:@"screen_fragment"];
    pipeline.colorAttachments[0].pixelFormat=self.colorPixelFormat;
    _pipeline=[device newRenderPipelineStateWithDescriptor:pipeline error:&error];
    requireDoom(_pipeline!=nil,"render pipeline failed");
    MTLTextureDescriptor* texture=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:DOOMGENERIC_RESX height:DOOMGENERIC_RESY mipmapped:NO];
    texture.storageMode=MTLStorageModeShared;texture.usage=MTLTextureUsageShaderRead;
    _image=[device newTextureWithDescriptor:texture];requireDoom(_image!=nil,"frame texture allocation failed");
    return self;
}
- (void)presentFrame {
    [_image replaceRegion:MTLRegionMake2D(0,0,DOOMGENERIC_RESX,DOOMGENERIC_RESY) mipmapLevel:0
        withBytes:DG_ScreenBuffer bytesPerRow:DOOMGENERIC_RESX*4];
    [self draw];
}
- (void)drawInMTKView:(MTKView*)view {
    id<CAMetalDrawable> drawable=self.currentDrawable;
    MTLRenderPassDescriptor* pass=self.currentRenderPassDescriptor;
    if (!drawable || !pass) return;
    id<MTLCommandBuffer> command=[_queue commandBuffer];
    id<MTLRenderCommandEncoder> render=[command renderCommandEncoderWithDescriptor:pass];
    [render setRenderPipelineState:_pipeline];[render setFragmentTexture:_image atIndex:0];
    // Doom's 320x200 pixels were displayed as 4:3 on a CRT. Letterbox on resize.
    double w=drawable.texture.width,h=drawable.texture.height;
    double width=w,height=w*.75;if (height>h) {height=h;width=h/0.75;}
    [render setViewport:(MTLViewport){(w-width)*.5,(h-height)*.5,width,height,0,1}];
    [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[render endEncoding];
    [command presentDrawable:drawable];[command commit];[command waitUntilCompleted];
    requireDoom(command.error==nil,"GPU command failed");

}
- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {}
@end

@interface DoomWindowDelegate : NSObject<NSWindowDelegate>
@end
@implementation DoomWindowDelegate
- (void)windowWillClose:(NSNotification*)notification { running=false;[NSApp stop:nil]; }
- (void)gameTick:(NSTimer*)timer { @autoreleasepool { if (running) doomgeneric_Tick(); } }
- (void)windowDidResignKey:(NSNotification*)notification { releaseKeys(); }
@end
static NSWindow* window;
static DoomView* view;
static DoomWindowDelegate* windowDelegate;
extern "C" void DG_Init() {
    [NSApplication sharedApplication];[NSApp finishLaunching];
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();requireDoom(device!=nil,"Metal device unavailable");
    window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,960,720)
        styleMask:NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
    window.title=@"DOOM - Darling Metal 0.5.0";window.releasedWhenClosed=NO;
    windowDelegate=[DoomWindowDelegate new];window.delegate=windowDelegate;
    view=[[DoomView alloc] initWithFrame:NSMakeRect(0,0,960,720) device:device];
    view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [window setContentView:view];[window center];[window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:view];[NSApp activateIgnoringOtherApps:YES];
    std::printf("DOOM: Metal=%s; keyboard=AppKit; audio=AudioQueue\n",device.name.UTF8String);
}
extern "C" void DG_DrawFrame() { if (applicationReady) { @autoreleasepool { [view presentFrame]; } } }
extern "C" void DG_SleepMs(uint32_t ms) { struct timespec delay={ms/1000,long(ms%1000)*1000000};nanosleep(&delay,nullptr); }
extern "C" uint32_t DG_GetTicksMs() { struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return uint32_t(uint64_t(t.tv_sec)*1000+t.tv_nsec/1000000); }
extern "C" int DG_GetKey(int* pressed,unsigned char* code) {
    return input.pop(pressed,code);
}
extern "C" void DG_SetWindowTitle(const char* title) {}
int main(int argc,char** argv) {
    @autoreleasepool {
        std::setbuf(stdout,nullptr);
        // Keep the engine's relative config/save paths in a persistent folder
        // chosen by the launcher, outside the disposable Darling prefix.
        if (argc>=3 && std::strcmp(argv[1],"--state-dir")==0) {
            requireDoom(chdir(argv[2])==0,"cannot open state directory");
            for (int n=1;n+2<argc;++n) argv[n]=argv[n+2];
            argc-=2;argv[argc]=nullptr;
        }
        doomgeneric_Create(argc,argv);
        I_AtExit(engineQuit,false);
        applicationReady=true;
        NSTimer* timer=[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:windowDelegate
            selector:@selector(gameTick:) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        [NSApp run];[timer invalidate];
        if (!engineExited) I_Quit();
        extern void doomAudioStop();doomAudioStop();
    }
    return 0;
}
