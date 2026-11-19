// SPDX-License-Identifier: GPL-3.0-or-later
// Public MSL derivatives and SPIR-V OpDPdx/OpDPdy: linear framebuffer functions.
#import <Metal/Metal.h>
#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <string>
static void requireDerivative(bool condition,const char* message) {if (!condition) throw std::runtime_error(message);}
int main() {@autoreleasepool {try {
    auto device=MTLCreateSystemDefaultDevice();requireDerivative(device!=nil,"no Metal device");
    auto queue=[device newCommandQueue];
    std::string source=R"(#include <metal_stdlib>
using namespace metal;
vertex float4 vertexMain(uint i [[vertex_id]]) {
    float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};
    return float4(p[i],0,1);
}
fragment float4 fragmentMain(float4 p [[position]],constant uint& mode [[buffer(0)]]) {
    float4 v=float4(.125*p.x,.25*p.y,.375*p.x+.125*p.y,.5*p.x-.25*p.y);
    if (mode==0) return dfdx(v);
    if (mode==1) return dfdy(v);
    return fwidth(v);
})";
    const float expected[3][4]={{.125f,0,.375f,.5f},{0,.25f,.125f,-.25f},{.125f,.25f,.5f,.75f}};
    for (unsigned mutant=0;mutant<2;++mutant) {
        auto shader=source;
        if (mutant) shader.replace(shader.find("dfdx(v)"),7,"dfdy(v)");
        NSError* error=nil;
        auto library=[device newLibraryWithSource:[NSString stringWithUTF8String:shader.c_str()] options:nil error:&error];
        if (!library) std::fprintf(stderr,"%s\n",error.description.UTF8String);
        requireDerivative(library!=nil,"derivative shader compilation failed");
        auto descriptor=[MTLRenderPipelineDescriptor new];
        descriptor.vertexFunction=[library newFunctionWithName:@"vertexMain"];
        descriptor.fragmentFunction=[library newFunctionWithName:@"fragmentMain"];
        descriptor.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA32Float;
        auto pipeline=[device newRenderPipelineStateWithDescriptor:descriptor error:&error];requireDerivative(pipeline!=nil,"derivative pipeline failed");
        auto textureDescriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:64 height:64 mipmapped:NO];
        textureDescriptor.storageMode=MTLStorageModeShared;textureDescriptor.usage=MTLTextureUsageRenderTarget;
        auto texture=[device newTextureWithDescriptor:textureDescriptor];requireDerivative(texture!=nil,"derivative target failed");
        size_t checked=0,mismatches=0;
        for (unsigned mode=0;mode<3;++mode) {
            auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture=texture;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
            auto command=[queue commandBuffer];auto encoder=[command renderCommandEncoderWithDescriptor:pass];
            [encoder setRenderPipelineState:pipeline];[encoder setViewport:MTLViewport{0,0,64,64,0,1}];
            [encoder setFragmentBytes:&mode length:4 atIndex:0];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[encoder endEncoding];
            [command commit];[command waitUntilCompleted];requireDerivative(command.error==nil,"derivative GPU command failed");
            float pixels[64*64*4];[texture getBytes:pixels bytesPerRow:64*16 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
            for (unsigned y=2;y<62;++y) for (unsigned x=2;x<62;++x) for (unsigned lane=0;lane<4;++lane) {
                float got=pixels[(y*64+x)*4+lane];++checked;
                mismatches+=!std::isfinite(got)||std::abs(got-expected[mode][lane])>1e-5f;
            }
        }
        std::printf("DERIVATIVES device=%s mutant=%u values=%zu mismatches=%zu\n",device.name.UTF8String,mutant,checked,mismatches);
        requireDerivative(mutant?mismatches>1000:mismatches==0,"derivative values or negative control failed");
    }
    std::puts("PASS derivative magnitude, sign, distinct vector lanes, fwidth and swapped-axis negative control");return 0;
} catch(const std::exception& error) {std::fprintf(stderr,"FAIL %s\n",error.what());return 1;}}}
