// SPDX-License-Identifier: GPL-3.0-or-later
#import "texture-operations.h"
#include "metal-baseline-source.h"
#include "cube-scene.hpp"
#include <vector>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {
void requireTexture(bool value,const char* text) {
    if (!value) { std::fprintf(stderr,"FAIL storage texture: %s\n",text);std::exit(1); }
}
}
@implementation TextureOperations
- (instancetype)initWithDevice:(id<MTLDevice>)device queue:(id<MTLCommandQueue>)queue {
    self=[super init];if (!self) return nil;
    _device=[device retain];_queue=[queue retain];NSError* error=nil;
    id<MTLLibrary> library=[device newLibraryWithSource:[NSString stringWithUTF8String:textureOpsShaderSource] options:nil error:&error];
    if (!library) std::fprintf(stderr,"Storage compiler: %s\n",[[error description] UTF8String]);
    requireTexture(library && !error,"read/write source compilation");
    id<MTLFunction> write=[library newFunctionWithName:@"upload_pixels"],read=[library newFunctionWithName:@"read_pixels"];
    _write=[device newComputePipelineStateWithFunction:write error:&error];requireTexture(_write && !error,"write pipeline");
    _read=[device newComputePipelineStateWithFunction:read error:&error];requireTexture(_read && !error,"read pipeline");
    id<MTLFunction> modify=[library newFunctionWithName:@"modify_pixels"];
    _modify=[device newComputePipelineStateWithFunction:modify error:&error];requireTexture(_modify && !error,"read_write pipeline");[modify release];
    [write release];[read release];[library release];return self;
}
- (void)dispatch:(id<MTLComputePipelineState>)pipeline buffer:(id<MTLBuffer>)buffer texture:(id<MTLTexture>)texture {
    uint32_t extent[]={uint32_t(texture.width),uint32_t(texture.height),0,0};
    id<MTLCommandBuffer> command=[_queue commandBuffer];id<MTLComputeCommandEncoder> encoder=[command computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];[encoder setBuffer:buffer offset:0 atIndex:5];
    [encoder setBytes:extent length:sizeof(extent) atIndex:7];[encoder setTexture:texture atIndex:3];
    // These kernels explicitly guard their image bounds. Dispatch full groups
    // so odd image dimensions do not require nonuniform threadgroup support.
    [encoder dispatchThreadgroups:MTLSizeMake((texture.width+3)/4,(texture.height+3)/4,1)
        threadsPerThreadgroup:MTLSizeMake(4,4,1)];
    [encoder endEncoding];[command commit];[command waitUntilCompleted];requireTexture(command.error==nil,"compute completion");
}
- (void)uploadRGBA:(const unsigned char*)pixels width:(NSUInteger)width height:(NSUInteger)height toTexture:(id<MTLTexture>)texture {
    requireTexture(width==texture.width && height==texture.height && width && height,"upload dimensions");
    std::vector<Cube::Float4> rgba(width*height);
    for (size_t i=0;i<rgba.size();++i) rgba[i]={pixels[i*4]/255.f,pixels[i*4+1]/255.f,pixels[i*4+2]/255.f,pixels[i*4+3]/255.f};
    id<MTLBuffer> buffer=[_device newBufferWithBytes:rgba.data() length:rgba.size()*sizeof(Cube::Float4) options:MTLResourceStorageModeShared];
    requireTexture(buffer!=nil,"upload buffer");[self dispatch:_write buffer:buffer texture:texture];[buffer release];
}
- (void)verify {
    for (unsigned mode=0;mode<2;++mode) {
        const unsigned width=mode?7:8,height=mode?5:8;
        std::vector<unsigned char> authored(width*height*4),poison(authored.size(),0xa5),actual(authored.size());
        for (unsigned y=0;y<height;++y) for (unsigned x=0;x<width;++x) {
            size_t i=(size_t(y)*width+x)*4;authored[i]=x*29;authored[i+1]=y*31;authored[i+2]=37+x*3+y*7;authored[i+3]=255;
        }
        MTLTextureDescriptor* descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
        descriptor.storageMode=MTLStorageModeShared;descriptor.usage=MTLTextureUsageShaderWrite;
        id<MTLTexture> written=[_device newTextureWithDescriptor:descriptor];requireTexture(written!=nil,"write-only texture");
        [written replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:poison.data() bytesPerRow:width*4];
        [self uploadRGBA:authored.data() width:width height:height toTexture:written];
        [written getBytes:actual.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];
        for (size_t i=0;i<actual.size();++i) requireTexture(std::abs(int(actual[i])-int(authored[i]))<=1,"GPU write matches authored pixels and replaces poison");
        descriptor.usage=MTLTextureUsageShaderRead;
        id<MTLTexture> readOnly=[_device newTextureWithDescriptor:descriptor];requireTexture(readOnly!=nil,"read-only texture");
        [readOnly replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:authored.data() bytesPerRow:width*4];
        std::vector<float> readback(width*height*4,-9);
        id<MTLBuffer> output=[_device newBufferWithBytes:readback.data() length:readback.size()*sizeof(float) options:MTLResourceStorageModeShared];
        requireTexture(output && output.contents,"read result storage");
        [self dispatch:_read buffer:output texture:readOnly];
        std::memcpy(readback.data(),output.contents,readback.size()*sizeof(float));
        for (size_t i=0;i<readback.size();++i) requireTexture(std::abs(readback[i]-authored[i]/255.f)<.0001f,"GPU read returns normalized texture values");
        descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
        id<MTLTexture> inPlace=[_device newTextureWithDescriptor:descriptor];requireTexture(inPlace!=nil,"read_write texture");
        [inPlace replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:authored.data() bytesPerRow:width*4];
        for (unsigned pass=0;pass<2;++pass) {
            [self dispatch:_modify buffer:nil texture:inPlace];
            [inPlace getBytes:actual.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];
            for (size_t i=0;i<actual.size();++i) {
                size_t expected=i;
                if (pass==0 && i%4==0) expected=i+2;
                if (pass==0 && i%4==2) expected=i-2;
                requireTexture(std::abs(int(actual[i])-int(authored[expected]))<=1,"in-place read/modify/write and reverse pass match CPU reference");
            }
        }
        [inPlace release];[output release];[readOnly release];[written release];
        std::printf("PASS storage textures read/write/read_write %ux%u, minimum usage flags and padded dispatch\n",width,height);
    }
}
- (void)dealloc { [_write release];[_read release];[_modify release];[_queue release];[_device release];[super dealloc]; }
@end
