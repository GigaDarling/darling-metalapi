// SPDX-License-Identifier: GPL-3.0-or-later
// Public Metal API client and its intentional conformance/scene checks.
#import "cube-renderer.h"
#include "cube-validation.hpp"
#include "metal-baseline-source.h"
#include <cstdio>
#include <cstdlib>
#include <string>

static void requireCube(bool condition, const char* message) {
    if (!condition) { std::fprintf(stderr,"FAIL cube: %s\n",message); std::exit(1); }
}

@implementation CubeRenderer
- (instancetype)initWithDevice: (id<MTLDevice>)device queue: (id<MTLCommandQueue>)queue {
    self = [super init];
    if (!self) return nil;
    _device = [device retain]; _queue = [queue retain];
    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:
        [NSString stringWithUTF8String: cubeShaderSource] options: nil error: &error];
    if (!library) std::fprintf(stderr,"Cube compiler: %s\n",[[error description] UTF8String]);
    requireCube(library && !error,"source compilation");
    id<MTLFunction> vertex = [library newFunctionWithName: @"cube_vertex"];
    id<MTLFunction> fragment = [library newFunctionWithName: @"cube_fragment"];
    MTLRenderPipelineDescriptor* pipeline = [MTLRenderPipelineDescriptor new];
    pipeline.vertexFunction = vertex; pipeline.fragmentFunction = fragment;
    pipeline.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipeline.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
    _pipeline = [device newRenderPipelineStateWithDescriptor: pipeline error: &error];
    requireCube(_pipeline && !error,"depth-enabled render pipeline");
    auto vertices = Cube::vertices(); auto indices = Cube::indices();
    _vertices = [device newBufferWithBytes: vertices.data() length: sizeof(vertices) options: MTLResourceStorageModeShared];
    _indices = [device newBufferWithBytes: indices.data() length: sizeof(indices) options: MTLResourceStorageModeShared];
    requireCube(_vertices && _indices,"24 vertices and 36 uint16 indices");
    MTLDepthStencilDescriptor* depth = [MTLDepthStencilDescriptor new];
    depth.depthCompareFunction = MTLCompareFunctionLess; depth.depthWriteEnabled = YES;
    _depthState = [device newDepthStencilStateWithDescriptor: depth];
    depth.depthCompareFunction = MTLCompareFunctionAlways; depth.depthWriteEnabled = NO;
    _alwaysState = [device newDepthStencilStateWithDescriptor: depth];
    requireCube(_depthState && _alwaysState,"depth comparison states");
    [depth release]; [pipeline release]; [vertex release]; [fragment release]; [library release];
    std::printf("PASS cube perspective, indexed geometry, source buffers 3/7 and depth states\n");
    return self;
}

- (void)encode: (id<MTLCommandBuffer>)command texture: (id<MTLTexture>)texture
          time: (float)time reverse: (BOOL)reverse depth: (BOOL)depth {
    if (!_depthTexture || _depthTexture.width != texture.width || _depthTexture.height != texture.height) {
        // MTKView's automatic depth texture is not implemented yet; the client
        // owns an ordinary public Metal depth resource and recreates it on resize.
        MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
            MTLPixelFormatDepth32Float width: texture.width height: texture.height mipmapped: NO];
        descriptor.usage = MTLTextureUsageRenderTarget; descriptor.storageMode = MTLStorageModePrivate;
        id<MTLTexture> replacement = [_device newTextureWithDescriptor: descriptor];
        requireCube(replacement != nil,"depth texture allocation");
        [_depthTexture release]; _depthTexture = replacement;
    }
    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColor {0.04,0.06,0.10,1};
    pass.depthAttachment.texture = _depthTexture; pass.depthAttachment.clearDepth = 1;
    pass.depthAttachment.loadAction = MTLLoadActionClear; pass.depthAttachment.storeAction = MTLStoreActionDontCare;
    id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor: pass];
    requireCube(encoder != nil,"render encoder with color/depth attachments");
    [encoder setRenderPipelineState: _pipeline];
    [encoder setDepthStencilState: depth ? _depthState : _alwaysState];
    [encoder setCullMode: MTLCullModeNone];
    [encoder setViewport: MTLViewport {0,0,double(texture.width),double(texture.height),0,1}];
    [encoder setVertexBuffer: _vertices offset: 0 atIndex: 3];
    auto uniforms = Cube::uniforms(texture.width,texture.height,time);
    [encoder setVertexBytes: &uniforms length: sizeof(uniforms) atIndex: 7];
    for (unsigned i = 0; i < 6; ++i) {
        unsigned face = reverse ? 5-i : i;
        [encoder drawIndexedPrimitives: MTLPrimitiveTypeTriangle indexCount: 6 indexType: MTLIndexTypeUInt16
            indexBuffer: _indices indexBufferOffset: face * 6 * sizeof(uint16_t)];
    }
    [encoder endEncoding];
}

- (void)encode: (id<MTLCommandBuffer>)command texture: (id<MTLTexture>)texture time: (float)time {
    [self encode: command texture: texture time: time reverse: NO depth: YES];
}

- (void)verifyOffscreen: (const char*)path {
    std::string stem(path);
    if (stem.size() >= 4 && stem.substr(stem.size()-4) == ".ppm") stem.resize(stem.size()-4);
    const unsigned sizes[][2] = {{640,480},{640,480},{640,480},{480,640}};
    const float times[] = {0,0.7f,1.4f,2.1f};
    std::vector<unsigned char> previous;
    for (unsigned frame = 0; frame < 4; ++frame) {
        unsigned width = sizes[frame][0], height = sizes[frame][1];
        MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
            MTLPixelFormatBGRA8Unorm width: width height: height mipmapped: NO];
        descriptor.usage = MTLTextureUsageRenderTarget; descriptor.storageMode = MTLStorageModeShared;
        id<MTLTexture> texture = [_device newTextureWithDescriptor: descriptor];
        requireCube(texture != nil,"offscreen color texture");
        std::vector<unsigned char> pixels(size_t(width)*height*4), forward;
        for (BOOL reverse : {NO,YES}) {
            id<MTLCommandBuffer> command = [_queue commandBuffer];
            [self encode: command texture: texture time: times[frame] reverse: reverse depth: YES];
            [command commit]; [command waitUntilCompleted];
            requireCube(command.error == nil,"command completion");
            [texture getBytes: pixels.data() bytesPerRow: width*4 fromRegion: MTLRegionMake2D(0,0,width,height) mipmapLevel: 0];
            auto result = Cube::validate(pixels,width,height,times[frame]);
            size_t faces = 0, interior = 0;
            for (size_t count : result.faces) { faces += count > 100; interior += count; }
            std::printf("CUBE t=%.1f size=%ux%u reverse=%d checked=%zu mismatches=%zu faces=%zu interior=%zu\n",
                times[frame],width,height,int(reverse),result.checked,result.mismatches,faces,interior);
            requireCube(result.checked > size_t(width)*height*9/10 && result.mismatches == 0,
                        "pixels match independent ray/box intersections");
            requireCube(faces >= 2 && interior > 10000,"multiple visible 3D faces");
            if (!reverse) forward = pixels;
            else {
                // The Less comparison does not select a unique color for coincident
                // face-edge samples. Test occlusion away from those ties, using the
                // same geometric edge band as the analytic reference.
                // Contract: developer.apple.com/documentation/metal/mtldepthstencildescriptor/depthcomparefunction
                size_t orderMismatches = 0, edgeDifferences = 0;
                for (unsigned y = 0; y < height; ++y) for (unsigned x = 0; x < width; ++x) {
                    size_t offset = (size_t(y)*width+x)*4;
                    if (std::equal(pixels.begin()+offset,pixels.begin()+offset+4,forward.begin()+offset)) continue;
                    int face = Cube::rayFace(x+.5f,y+.5f,width,height,times[frame]);
                    if (Cube::stablePixel(x+.5f,y+.5f,width,height,times[frame],face)) ++orderMismatches;
                    else ++edgeDifferences;
                }
                std::printf("DEPTH order_mismatches=%zu edge_ties=%zu\n",orderMismatches,edgeDifferences);
                requireCube(orderMismatches == 0,"depth preserves interior pixels under reversed face submission");
            }
        }
        if (frame && sizes[frame-1][0] == width) {
            size_t changes = 0;
            for (size_t i = 0; i < pixels.size(); ++i) changes += pixels[i] != previous[i];
            requireCube(changes > 1000,"rotation changes successive frames");
        }
        previous = pixels;
        FILE* file = std::fopen((stem+"-"+std::to_string(frame)+".ppm").c_str(),"wb");
        requireCube(file != nullptr,"open image"); std::fprintf(file,"P6\n%u %u\n255\n",width,height);
        for (size_t i = 0; i < size_t(width)*height; ++i) {
            unsigned char rgb[] = {pixels[i*4+2],pixels[i*4+1],pixels[i*4]};
            requireCube(std::fwrite(rgb,1,3,file)==3,"write image");
        }
        requireCube(std::fclose(file)==0,"close image");
        id<MTLCommandBuffer> wrong = [_queue commandBuffer];
        [self encode: wrong texture: texture time: times[frame] reverse: YES depth: NO];
        [wrong commit]; [wrong waitUntilCompleted];
        [texture getBytes: pixels.data() bytesPerRow: width*4 fromRegion: MTLRegionMake2D(0,0,width,height) mipmapLevel: 0];
        requireCube(Cube::validate(pixels,width,height,times[frame]).mismatches > 1000,
                    "negative control rejects disabled depth comparison");
        std::fill(pixels.begin(),pixels.end(),0);
        requireCube(Cube::validate(pixels,width,height,times[frame]).mismatches > 1000,"negative control rejects blank image");
        [texture release];
    }
    std::printf("PASS cube rotation, perspective/aspect, depth occlusion, reversed face order and negative controls\n");
}

- (void)dealloc {
    [_depthTexture release]; [_alwaysState release]; [_depthState release];
    [_vertices release]; [_indices release]; [_pipeline release]; [_queue release]; [_device release];
    [super dealloc];
}
@end
