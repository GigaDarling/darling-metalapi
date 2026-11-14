// SPDX-License-Identifier: GPL-3.0-or-later
// A public Metal/MetalKit API client. Its verification output belongs to this
// test tool; no instrumentation is inserted into framework render paths.
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "metal-baseline-source.h"
#include "scene-validation.hpp"
#include <string>
#import "cube-renderer.h"
#import "material-renderer.h"

static MTLClearColor background() { return MTLClearColor {0.04, 0.06, 0.10, 1.0}; }
static BOOL windowChecks = NO;
static BOOL shapesMode = NO;
static BOOL cubeMode = NO;
static BOOL materialsMode = NO;
static void expectMetal(bool condition, const char* message) {
    if (!condition) { std::fprintf(stderr, "FAIL %s\n", message); std::exit(1); }
}

// Cold-start integration check for the updated open Metal implementation.
static void verifyUpstreamValueAPIs() {
    MTLCompileOptions* options=[MTLCompileOptions new];
    options.fastMathEnabled=NO;
    expectMetal(options.mathMode==MTLMathModeSafe,"compile options safe math round trip");
    options.mathMode=MTLMathModeFast;
    expectMetal(options.fastMathEnabled,"compile options fast math alias");
    options.preprocessorMacros=@{@"API_TEST":@7};
    options.languageVersion=MTLLanguageVersion3_2;
    MTLCompileOptions* copy=[options copy];options.preprocessorMacros=@{@"API_TEST":@8};
    expectMetal([copy.preprocessorMacros[@"API_TEST"] intValue]==7 && copy.languageVersion==MTLLanguageVersion3_2,
        "compile options independently preserve copied public values");
    [copy release];[options release];
    FILE* maps=std::fopen("/Volumes/SystemRoot/proc/self/maps","r");
    if (maps) {
        bool loaded=false;char line[1024];
        while (std::fgets(line,sizeof(line),maps)) if (std::strstr(line,"libvulkan")) loaded=true;
        std::fclose(maps);expectMetal(!loaded,"loading Metal and its value objects leaves Vulkan uninitialized");
        std::printf("PASS lazy Metal initialization before requesting a device\n");
    }
    std::printf("PASS updated upstream compile-options value and copy APIs\n");
}

@interface EarlyLayerView : NSView
@end
@implementation EarlyLayerView
- (instancetype)initWithFrame: (NSRect)frame {
    self.wantsLayer = YES;
    return [super initWithFrame: frame];
}
@end

@interface BaselineRenderer : NSObject <MTKViewDelegate, NSApplicationDelegate, NSWindowDelegate> {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    NSWindow* _window;
    MTKView* _view;
    NSUInteger _frames;
    NSUInteger _windowCheckStep;
    id<MTLRenderPipelineState> _shapePipeline;
    id<MTLBuffer> _shapeBuffers[3];
    NSUInteger _shapeVertexCounts[3];
    CFTimeInterval _animationStart;
    NSUInteger _lastCheckFrames;
    CubeRenderer* _cube;
    MaterialRenderer* _materials;
    NSButton* _materialButtons[2];
    NSTextField* _materialLabel;
    NSButton* _lightingButton;
}
- (void)verifyOffscreen: (const char*)path;
- (void)verifyShapes: (const char*)path;
- (void)verifyCube: (const char*)path;
- (void)verifyMaterials: (const char*)path;
@end

@implementation BaselineRenderer
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    EarlyLayerView* early = [[EarlyLayerView alloc] initWithFrame: NSMakeRect(0, 0, 123, 87)];
    expectMetal(early.alphaValue == 1.0 && early.layer.opacity == 1.0 &&
                early.layer.bounds.size.width == 123 && early.layer.bounds.size.height == 87,
                "NSView initializes an already-created backing layer consistently");
    [early release];
    _device = MTLCreateSystemDefaultDevice();
    expectMetal(_device != nil, "MTLCreateSystemDefaultDevice");
    std::printf("DEVICE %s\n", [_device.name UTF8String]);
    auto tier=[_device argumentBuffersSupport];
    expectMetal(tier==MTLArgumentBuffersTier1 || tier==MTLArgumentBuffersTier2,"upstream argument-buffer tier query");
    (void)[_device supportsShaderBarycentricCoordinates];
    NSError* error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:
        [NSString stringWithUTF8String: baselineShaderSource] options: nil error: &error];
    if (!library) std::fprintf(stderr, "Compiler: %s\n", [[error description] UTF8String]);
    expectMetal(library && !error, "source library compilation");
    expectMetal([library.functionNames containsObject: @"baseline_vertex"] &&
            [library.functionNames containsObject: @"baseline_fragment"], "source library functionNames");
    expectMetal([library newFunctionWithName: @"missing_baseline_function"] == nil, "missing function returns nil");
    id<MTLFunction> vertex = [library newFunctionWithName: @"baseline_vertex"];
    id<MTLFunction> fragment = [library newFunctionWithName: @"baseline_fragment"];
    expectMetal(vertex.functionType == MTLFunctionTypeVertex && fragment.functionType == MTLFunctionTypeFragment,
            "source library stage reflection");

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertex;
    descriptor.fragmentFunction = fragment;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _pipeline = [_device newRenderPipelineStateWithDescriptor: descriptor error: &error];
    if (!_pipeline) std::fprintf(stderr, "Pipeline: %s\n", [[error description] UTF8String]);
    expectMetal(_pipeline != nil && !error, "render pipeline creation");
    _queue = [_device newCommandQueue];
    expectMetal(_queue != nil, "command queue");
    [descriptor release]; [vertex release]; [fragment release]; [library release];

    error = nil;
    expectMetal([_device newLibraryWithSource: @"fragment float4 invalid( {" options: nil error: &error] == nil
            && [error.domain isEqualToString: MTLLibraryErrorDomain] && error.code == MTLLibraryErrorCompileFailure,
            "invalid source reports a compilation NSError");
    expectMetal([_device newLibraryWithSource: @"fragment float4 invalid( {" options: nil error: nullptr] == nil,
            "invalid source tolerates a null error output");
    MTLCompileOptions* customOptions = [[MTLCompileOptions alloc] init];
    error = nil;
    expectMetal([_device newLibraryWithSource: [NSString stringWithUTF8String: baselineShaderSource]
                options: customOptions error: &error] == nil && error.code == MTLLibraryErrorUnsupported,
                "unsupported compile options report an error");
    [customOptions release];
    error = nil;
    id<MTLLibrary> resourceLibrary = [_device newLibraryWithSource:
        @"#include <metal_stdlib>\nusing namespace metal;\nkernel void resource_probe(device float* output [[buffer(5)]]) { output[0] = 1.0f; }"
        options: nil error: &error];
    expectMetal(resourceLibrary && !error, "source buffer resources compile");
    id<MTLFunction> function = [resourceLibrary newFunctionWithName: @"resource_probe"];
    id<MTLComputePipelineState> compute = [_device newComputePipelineStateWithFunction: function error: &error];
    expectMetal(compute && !error, "source buffer compute pipeline");
    float poison = -9;
    id<MTLBuffer> output = [_device newBufferWithBytes: &poison length: sizeof(poison)
        options: MTLResourceStorageModeShared];
    expectMetal(output && output.contents && output.length == sizeof(float), "shared compute buffer storage");
    float readback;
    std::memcpy(&readback, output.contents, sizeof(readback));
    expectMetal(readback != 1, "buffer readback has a non-result initial value");
    id<MTLCommandBuffer> command = [_queue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    [encoder setComputePipelineState: compute];
    [encoder setBuffer: output offset: 0 atIndex: 5];
    [encoder dispatchThreads: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
    [encoder endEncoding]; [command enqueue]; [command commit]; [command waitUntilScheduled]; [command waitUntilCompleted];
    std::memcpy(&readback, output.contents, sizeof(readback));
    expectMetal(readback == 1, "source buffer at a nonzero Metal index writes the expected value");
    [output release]; [compute release]; [function release]; [resourceLibrary release];
    error = nil;
    id<MTLLibrary> sampled = [_device newLibraryWithSource:
        @"#include <metal_stdlib>\nusing namespace metal;\nfragment float4 texture_probe(texture2d<float> image [[texture(2)]], sampler sampling [[sampler(4)]]) { return image.sample(sampling, float2(0.5f, 0.5f)); }"
        options:nil error:&error];
    expectMetal(sampled && !error,"source sampled texture and sampler resources compile");
    [sampled release];
    error=nil;
    id<MTLLibrary> embedded=[_device newLibraryWithSource:
        @"#include <metal_stdlib>\nusing namespace metal;\nfragment float4 embedded_probe(texture2d<float> image [[texture(0)]]) { constexpr sampler filtering(coord::normalized, address::repeat, filter::linear); return image.sample(filtering,float2(.5f,.5f)); }"
        options:nil error:&error];
    expectMetal(embedded && !error,"embedded source sampler compiles");[embedded release];
    std::printf("PASS source buffer reflection and compute readback at index 5\n");
    if (shapesMode) [self prepareShapes];
    if (materialsMode) _materials = [[MaterialRenderer alloc] initWithDevice:_device queue:_queue];
    if (cubeMode) _cube = [[CubeRenderer alloc] initWithDevice: _device queue: _queue];
    std::printf("PASS public source compilation, function lookup, errors and pipeline\n");
    return self;
}

- (void)verifyCube: (const char*)path { [_cube verifyOffscreen: path]; }
- (void)verifyMaterials: (const char*)path { [_materials verifyOffscreen:path]; }

- (void)toggleLighting:(NSButton*)sender { _materials.lightingEnabled=[sender state]==NSControlStateValueOn; }

- (void)chooseMaterial: (NSButton*)sender {
    _materials.selection=[sender tag];
    for (unsigned i=0;i<2;++i) [_materialButtons[i] setState:i==_materials.selection ? NSControlStateValueOn : NSControlStateValueOff];
    [_materialLabel setStringValue:_materials.selection==0 ? @"Бетон   |   2D текстура → 3D куб" : @"Дерево   |   2D текстура → 3D куб"];
}

- (void)prepareShapes {
    NSError* error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:
        [NSString stringWithUTF8String: shapesShaderSource] options: nil error: &error];
    if (!library) std::fprintf(stderr, "Shapes compiler: %s\n", [[error description] UTF8String]);
    expectMetal(library && !error, "shapes source compilation");
    id<MTLFunction> vertex = [library newFunctionWithName: @"shapes_vertex"];
    id<MTLFunction> fragment = [library newFunctionWithName: @"shapes_fragment"];
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment;
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _shapePipeline = [_device newRenderPipelineStateWithDescriptor: descriptor error: &error];
    if (!_shapePipeline) std::fprintf(stderr, "Shapes pipeline: %s\n", [[error description] UTF8String]);
    expectMetal(_shapePipeline && !error, "shapes render pipeline");
    for (unsigned i = 0; i < 3; ++i) {
        auto vertices = Shapes::geometry(i);
        _shapeVertexCounts[i] = vertices.size();
        _shapeBuffers[i] = [_device newBufferWithBytes: vertices.data()
            length: vertices.size() * sizeof(Shapes::Float4) options: MTLResourceStorageModeShared];
        expectMetal(_shapeBuffers[i] != nil, "shape geometry buffer");
    }
    [descriptor release]; [vertex release]; [fragment release]; [library release];
    std::printf("PASS square, disk and ring geometry; vertex buffers at indices 3 and 7\n");
}

- (void)encodeShapes: (id<MTLCommandBuffer>)command texture: (id<MTLTexture>)texture time: (float)time {
    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].clearColor = background();
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor: pass];
    expectMetal(encoder != nil, "shapes render encoder");
    [encoder setRenderPipelineState: _shapePipeline];
    [encoder setViewport: MTLViewport {0, 0, (double)texture.width, (double)texture.height, 0, 1}];
    auto objects = Shapes::scene(texture.width, texture.height, time);
    for (unsigned i = 0; i < objects.size(); ++i) {
        [encoder setVertexBuffer: _shapeBuffers[i] offset: 0 atIndex: 3];
        [encoder setVertexBytes: &objects[i].uniforms length: sizeof(Shapes::Uniforms) atIndex: 7];
        [encoder drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: _shapeVertexCounts[i]];
    }
    [encoder endEncoding];
}

- (void)verifyShapes: (const char*)path {
    const unsigned width = 640, height = 400;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
        MTLPixelFormatBGRA8Unorm width: width height: height mipmapped: NO];
    descriptor.usage = MTLTextureUsageRenderTarget;
    descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [_device newTextureWithDescriptor: descriptor];
    expectMetal(texture != nil, "shapes offscreen texture");
    std::vector<unsigned char> pixels(width * height * 4), previous;
    const float times[] = {0, 0.7f, 1.4f, 2.1f};
    std::string stem(path);
    if (stem.size() >= 4 && stem.substr(stem.size() - 4) == ".ppm") stem.resize(stem.size() - 4);
    for (unsigned frame = 0; frame < 4; ++frame) {
        id<MTLCommandBuffer> command = [_queue commandBuffer];
        [self encodeShapes: command texture: texture time: times[frame]];
        [command commit]; [command waitUntilCompleted];
        expectMetal(command.error == nil, "shapes command completion");
        [texture getBytes: pixels.data() bytesPerRow: width * 4
            fromRegion: MTLRegionMake2D(0, 0, width, height) mipmapLevel: 0];
        auto result = Shapes::validate(pixels, width, height, times[frame]);
        std::printf("SCENE t=%.1f checked=%lu mismatches=%lu square=%lu disk=%lu ring=%lu\n",
            times[frame], result.checked, result.mismatches,
            result.interiors[0], result.interiors[1], result.interiors[2]);
        expectMetal(result.checked > width * height * 9 / 10 && result.mismatches == 0,
                    "shape pixels match the independent analytic reference");
        for (size_t count : result.interiors) expectMetal(count > 500, "every shape has a visible interior");
        if (!previous.empty()) {
            size_t changes = 0;
            for (size_t i = 0; i < pixels.size(); ++i) changes += pixels[i] != previous[i];
            expectMetal(changes > 1000, "successive animation frames differ");
        }
        previous = pixels;
        FILE* output = std::fopen((stem + "-" + std::to_string(frame) + ".ppm").c_str(), "wb");
        expectMetal(output != nullptr, "open shapes image");
        std::fprintf(output, "P6\n%u %u\n255\n", width, height);
        for (size_t i = 0; i < width * height; ++i) {
            unsigned char rgb[] = {pixels[i * 4 + 2], pixels[i * 4 + 1], pixels[i * 4]};
            expectMetal(std::fwrite(rgb, 1, 3, output) == 3, "write shapes image");
        }
        expectMetal(std::fclose(output) == 0, "close shapes image");
    }
    std::fill(pixels.begin(), pixels.end(), 0);
    expectMetal(Shapes::validate(pixels, width, height, times[3]).mismatches > 1000,
                "negative control rejects a blank animation frame");
    [texture release];
    std::printf("PASS four animation timestamps, square/circle/ring interiors and ring holes\n");
}

- (void)encode: (id<MTLCommandBuffer>)command texture: (id<MTLTexture>)texture triangle: (BOOL)triangle {
    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].clearColor = background();
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor: pass];
    expectMetal(encoder != nil, "render encoder");
    if (triangle) {
        [encoder setRenderPipelineState: _pipeline];
        [encoder setViewport: MTLViewport {0, 0, (double)texture.width, (double)texture.height, 0, 1}];
        [encoder drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: 3];
    }
    [encoder endEncoding];
}

- (void)verifyOffscreen: (const char*)path {
    const NSUInteger width = 256, height = 256;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
        MTLPixelFormatBGRA8Unorm width: width height: height mipmapped: NO];
    descriptor.usage = MTLTextureUsageRenderTarget;
    descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [_device newTextureWithDescriptor: descriptor];
    expectMetal(texture != nil, "offscreen texture");
    std::vector<unsigned char> pixels(width * height * 4);
    for (BOOL triangle : {NO, YES}) {
        id<MTLCommandBuffer> command = [_queue commandBuffer];
        [self encode: command texture: texture triangle: triangle];
        [command commit]; [command waitUntilCompleted];
        expectMetal(command.error == nil, "offscreen command completion");
        [texture getBytes: pixels.data() bytesPerRow: width * 4
            fromRegion: MTLRegionMake2D(0, 0, width, height) mipmapLevel: 0];
        NSUInteger clearCount = 0, triangleCount = 0;
        for (NSUInteger i = 0; i < width * height; ++i) {
            const auto* p = pixels.data() + i * 4;
            if (std::abs((int)p[0] - 26) <= 1 && std::abs((int)p[1] - 15) <= 1 &&
                std::abs((int)p[2] - 10) <= 1 && p[3] == 255) ++clearCount;
            if (p[0] == 255 && std::abs((int)p[1] - 153) <= 1 &&
                std::abs((int)p[2] - 51) <= 1 && p[3] == 255) ++triangleCount;
        }
        if (!triangle) expectMetal(clearCount == width * height, "clear-only pixel readback");
        else {
            std::printf("PIXELS clear=%lu triangle=%lu total=%lu\n", clearCount, triangleCount, width * height);
            expectMetal(triangleCount > width * height / 10 && triangleCount < width * height * 15 / 100,
                    "triangle covers the expected area");
            expectMetal(clearCount + triangleCount == width * height, "all pixels match the two expected colors");
        }
    }
    FILE* output = std::fopen(path, "wb");
    expectMetal(output != nullptr, "open readback image");
    std::fprintf(output, "P6\n%lu %lu\n255\n", width, height);
    for (NSUInteger i = 0; i < width * height; ++i) {
        unsigned char rgb[] = {pixels[i * 4 + 2], pixels[i * 4 + 1], pixels[i * 4]};
        expectMetal(std::fwrite(rgb, 1, 3, output) == 3, "write readback image");
    }
    expectMetal(std::fclose(output) == 0, "close readback image");
    [texture release];
    std::printf("PASS offscreen clear and triangle: %s\n", path);
}

- (void)applicationDidFinishLaunching: (NSNotification*)notification {
    (void)notification;
    _animationStart = CACurrentMediaTime();
    NSSize initialSize = materialsMode ? NSMakeSize(1000,650) : (shapesMode || cubeMode) ? NSMakeSize(900, 560) : NSMakeSize(720, 480);
    _window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, initialSize.width, initialSize.height)
        styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
        backing: NSBackingStoreBuffered defer: NO];
    [_window setTitle: materialsMode ? @"Darling Metal - Dynamic light and textures" : cubeMode ? @"Darling Metal - Rotating 3D cube" :
        shapesMode ? @"Darling Metal - Shapes in motion" : @"Darling Metal - Render verification"];
    [_window setReleasedWhenClosed: NO];
    [_window setDelegate: self];
    _view = [[MTKView alloc] initWithFrame: NSMakeRect(0, 0, initialSize.width, initialSize.height-(materialsMode?70:0)) device: _device];
    expectMetal(_view.layer.opacity == 1.0 && _view.alphaValue == 1.0,
                "MTKView creates its backing layer after NSView initializes alpha");
    expectMetal(NSEqualSizes(_view.drawableSize,_view.bounds.size),"MTKView initializes drawableSize before insertion into a window");
    _view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _view.clearColor = background();
    _view.delegate = self;
    [_view setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    if (materialsMode) {
        NSView* content=[[NSView alloc] initWithFrame:NSMakeRect(0,0,initialSize.width,initialSize.height)];
        [content addSubview:_view];
        for (unsigned i=0;i<2;++i) {
            NSButton* button=[[NSButton alloc] initWithFrame:NSMakeRect(20+i*165,initialSize.height-52,155,32)];
            [button setTitle:i==0?@"1. Бетон":@"2. Дерево"];
            [button setButtonType:NSPushOnPushOffButton];[button setTag:i];
            [button setTarget:self];[button setAction:@selector(chooseMaterial:)];
            [button setAutoresizingMask:NSViewMinYMargin];[content addSubview:button];_materialButtons[i]=button;
        }
        _lightingButton=[[NSButton alloc] initWithFrame:NSMakeRect(365,initialSize.height-52,190,32)];
        [_lightingButton setTitle:@"Динамический свет"];[_lightingButton setButtonType:NSPushOnPushOffButton];
        [_lightingButton setState:NSControlStateValueOn];[_lightingButton setTarget:self];[_lightingButton setAction:@selector(toggleLighting:)];
        [_lightingButton setAutoresizingMask:NSViewMinYMargin];[content addSubview:_lightingButton];
        _materialLabel=[[NSTextField alloc] initWithFrame:NSMakeRect(570,initialSize.height-51,405,30)];
        [_materialLabel setEditable:NO];[_materialLabel setSelectable:NO];[_materialLabel setBezeled:NO];[_materialLabel setDrawsBackground:NO];
        [_materialLabel setAutoresizingMask:NSViewWidthSizable|NSViewMinYMargin];[content addSubview:_materialLabel];
        [self chooseMaterial:_materialButtons[0]];
        [_window setContentView:content];[content release];
    } else [_window setContentView: _view];
    [_window center];
    [_window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    if (windowChecks)
        [NSTimer scheduledTimerWithTimeInterval: 1.0 target: self
            selector: @selector(checkWindow:) userInfo: nil repeats: YES];
}

- (void)checkWindow: (NSTimer*)timer {
    expectMetal(_frames > _lastCheckFrames, "window keeps submitting frames");
    _lastCheckFrames = _frames;
    const NSSize expected[] = {materialsMode ? NSMakeSize(1000,650) : (shapesMode || cubeMode) ? NSMakeSize(900, 560) : NSMakeSize(720, 480),
        NSMakeSize(900, 600), NSMakeSize(640, 420)};
    NSSize size = expected[_windowCheckStep];
    if (materialsMode) {
        [_materialButtons[_windowCheckStep==0?1:0] performClick:nil];
        expectMetal(_materials.selection==(_windowCheckStep==0?1:0),"material button action updates selection");
        [_lightingButton performClick:nil];
        expectMetal(_materials.lightingEnabled==(_windowCheckStep==1),"dynamic light toggle action updates renderer");
    }
    NSSize renderSize=NSMakeSize(size.width,size.height-(materialsMode?70:0));
    expectMetal(NSEqualSizes(_view.bounds.size, renderSize), "window content follows resize");
    expectMetal(NSEqualSizes(_view.drawableSize, renderSize), "Metal drawable follows resize");
    double elapsed = CACurrentMediaTime() - _animationStart;
    std::printf("PASS window size %.0fx%.0f, frames=%lu elapsed=%.2f fps=%.1f\n",
        size.width, size.height, _frames, elapsed, _frames / elapsed);
    std::fflush(stdout);
    if (++_windowCheckStep == 3) {
        [timer invalidate];
        [_window performClose: nil];
    } else {
        [_window setContentSize: expected[_windowCheckStep]];
    }
}
- (void)drawInMTKView: (MTKView*)view {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!drawable) return;
    id<MTLCommandBuffer> command = [_queue commandBuffer];
    if (materialsMode)
        [_materials encode:command texture:drawable.texture time:CACurrentMediaTime()-_animationStart];
    else if (cubeMode)
        [_cube encode: command texture: drawable.texture time: CACurrentMediaTime() - _animationStart];
    else if (shapesMode)
        [self encodeShapes: command texture: drawable.texture time: CACurrentMediaTime() - _animationStart];
    else
        [self encode: command texture: drawable.texture triangle: YES];
    [command presentDrawable: drawable];
    [command commit];
    if (++_frames == 1) { std::printf("PASS window frame submitted\n"); std::fflush(stdout); }
}
- (void)mtkView: (MTKView*)view drawableSizeWillChange: (CGSize)size { (void)view; (void)size; }
- (void)windowWillClose: (NSNotification*)notification {
    (void)notification;
    std::printf("PASS window close requested\n"); std::fflush(stdout);
    [NSApp terminate: nil];
}
- (void)dealloc {
    [_materials release];[_materialLabel release];[_lightingButton release];
    for (NSButton* button:_materialButtons) [button release];
    [_cube release];
    for (id<MTLBuffer> buffer : _shapeBuffers) [buffer release];
    [_shapePipeline release];
    [_view release]; [_window release]; [_pipeline release]; [_queue release]; [_device release];
    [super dealloc];
}
@end

int main(int argc, char** argv) {
    @autoreleasepool {
        expectMetal(argc == 2 || argc == 3, "Usage: metal-baseline-demo --[shapes-/cube-]offscreen image.ppm | --[shapes-/cube-]window | --[shapes-/cube-]window-test");
        verifyUpstreamValueAPIs();
        shapesMode = std::strncmp(argv[1], "--shapes-", 9) == 0;
        materialsMode = std::strncmp(argv[1], "--textures-", 11) == 0;
        cubeMode = std::strncmp(argv[1], "--cube-", 7) == 0;
        windowChecks = std::strcmp(argv[1], "--window-test") == 0 || std::strcmp(argv[1], "--shapes-window-test") == 0 ||
                       std::strcmp(argv[1], "--cube-window-test") == 0 || std::strcmp(argv[1], "--textures-window-test") == 0;
        if (std::strcmp(argv[1], "--window") == 0 || std::strcmp(argv[1], "--shapes-window") == 0 ||
            std::strcmp(argv[1], "--cube-window") == 0 || std::strcmp(argv[1], "--textures-window") == 0 || windowChecks) {
            NSApplication* app = [NSApplication sharedApplication];
            BaselineRenderer* renderer = [[BaselineRenderer alloc] init];
            [app setDelegate: renderer]; [app run]; [renderer release];
        } else {
            expectMetal(argc == 3 && (std::strcmp(argv[1], "--offscreen") == 0 ||
                        std::strcmp(argv[1], "--shapes-offscreen") == 0 ||
                        std::strcmp(argv[1], "--cube-offscreen") == 0 || std::strcmp(argv[1], "--textures-offscreen") == 0), "invalid demo arguments");
            BaselineRenderer* renderer = [[BaselineRenderer alloc] init];
            if (materialsMode) [renderer verifyMaterials:argv[2]];
            else if (cubeMode) [renderer verifyCube: argv[2]];
            else if (shapesMode) [renderer verifyShapes: argv[2]];
            else [renderer verifyOffscreen: argv[2]];
            [renderer release];
        }
    }
    return 0;
}
