// SPDX-License-Identifier: GPL-3.0-or-later
#import "material-renderer.h"
#include "cube-validation.hpp"
#include "material-textures.hpp"
#include "metal-baseline-source.h"
#include <cstdio>
#include <cstdlib>
#include <string>

namespace {
struct Vertex { Cube::Float4 position, detail; };
constexpr float shades[] = {0.98f,0.64f,0.82f,0.70f,1.0f,0.52f};
void requireMaterial(bool value,const char* message) {
    if (!value) { std::fprintf(stderr,"FAIL materials: %s\n",message); std::exit(1); }
}
struct Layout { unsigned right,side,left,top; };
Layout layout(unsigned width,unsigned height) {
    unsigned right=width*36/100,side=std::min(width*26/100,height*68/100);
    return {right,side,(right-side)/2,(height-side)/2};
}
std::array<double,4> sample(const std::vector<unsigned char>& data,double u,double v) {
    double sx=u*Materials::size-.5,sy=v*Materials::size-.5;
    int x=int(std::floor(sx)),y=int(std::floor(sy));
    double fx=sx-x,fy=sy-y;
    std::array<double,4> result {};
    for (int dy=0;dy<2;++dy) for (int dx=0;dx<2;++dx) {
        unsigned px=(x+dx+int(Materials::size))%Materials::size,py=(y+dy+int(Materials::size))%Materials::size;
        double weight=(dx?fx:1-fx)*(dy?fy:1-fy);
        for (unsigned c=0;c<4;++c) result[c]+=data[(size_t(py)*Materials::size+px)*4+c]*weight;
    }
    return result;
}
size_t validate(const std::vector<unsigned char>& bgra,unsigned width,unsigned height,float time,unsigned material) {
    auto image=Materials::texture(material);auto area=layout(width,height);
    size_t checked=0,mismatches=0,cube=0,preview=0;
    for (unsigned y=2;y+2<height;y+=3) for (unsigned x=2;x+2<width;x+=3) {
        std::array<double,4> expected {10.2,15.3,25.5,255};
        if (x<area.right) {
            if (x<=area.left+2 || x+2>=area.left+area.side || y<=area.top+2 || y+2>=area.top+area.side) continue;
            expected=sample(image,(x+.5-area.left)/area.side,(y+.5-area.top)/area.side);++preview;
        } else {
            unsigned local=x-area.right,w=width-area.right;
            std::array<double,3> hit {};
            int face=Cube::rayFace(local+.5f,y+.5f,w,height,time,&hit);
            if (!Cube::stablePixel(local+.5f,y+.5f,w,height,time,face)) continue;
            if (face>=0) {
                double u=0,v=0;
                if (face<2) { u=(1+(face==0?hit[0]:-hit[0]))*.5;v=(1-hit[1])*.5; }
                else if (face<4) { u=(1+(face==2?-hit[2]:hit[2]))*.5;v=(1-hit[1])*.5; }
                else { u=(1+hit[0])*.5;v=(1+(face==4?hit[2]:-hit[2]))*.5; }
                expected=sample(image,u,v);
                for (unsigned c=0;c<3;++c) expected[c]*=shades[face];
                ++cube;
            }
        }
        bool matches=true;
        for (unsigned c=0;c<4;++c)
            if (std::abs(int(bgra[(size_t(y)*width+x)*4+c])-std::lround(expected[c==0?2:c==2?0:c]))>(c==3?0:3)) matches=false;
        ++checked;mismatches+=!matches;
    }
    std::printf("MATERIAL material=%u t=%.1f checked=%zu mismatches=%zu preview=%zu cube=%zu\n",material,time,checked,mismatches,preview,cube);
    requireMaterial(preview>1000 && cube>1000,"flat preview and cube have independently checked interiors");
    return mismatches;
}
}

@implementation MaterialRenderer
@synthesize selection=_selection;
- (void)setSelection: (NSUInteger)selection {
    if (selection>1) [NSException raise:NSInvalidArgumentException format:@"Unknown material index"];
    _selection=selection;
}
- (instancetype)initWithDevice: (id<MTLDevice>)device queue: (id<MTLCommandQueue>)queue {
    self=[super init];if (!self) return nil;
    _device=[device retain];_queue=[queue retain];
    NSError* error=nil;
    id<MTLLibrary> library=[device newLibraryWithSource:[NSString stringWithUTF8String:materialsShaderSource] options:nil error:&error];
    if (!library) std::fprintf(stderr,"Material compiler: %s\n",[[error description] UTF8String]);
    requireMaterial(library && !error,"textured shader compilation");
    id<MTLFunction> vertex=[library newFunctionWithName:@"material_vertex"],fragment=[library newFunctionWithName:@"material_fragment"];
    MTLRenderPipelineDescriptor* pipeline=[MTLRenderPipelineDescriptor new];
    pipeline.vertexFunction=vertex;pipeline.fragmentFunction=fragment;
    pipeline.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;pipeline.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    _pipeline=[device newRenderPipelineStateWithDescriptor:pipeline error:&error];requireMaterial(_pipeline && !error,"textured depth pipeline");
    auto mesh=Cube::vertices();std::array<Vertex,24> vertices {};
    const float uv[4][2]={{0,1},{1,1},{1,0},{0,0}};
    for (unsigned i=0;i<24;++i) vertices[i]={mesh[i].position,{uv[i%4][0],uv[i%4][1],shades[i/4],0}};
    const Vertex quad[]={{{-1,-1,0,1},{0,1,1,0}},{{1,-1,0,1},{1,1,1,0}},{{1,1,0,1},{1,0,1,0}},{{-1,1,0,1},{0,0,1,0}}};
    auto indices=Cube::indices();
    _vertices=[device newBufferWithBytes:vertices.data() length:sizeof(vertices) options:MTLResourceStorageModeShared];
    _quad=[device newBufferWithBytes:quad length:sizeof(quad) options:MTLResourceStorageModeShared];
    _indices=[device newBufferWithBytes:indices.data() length:sizeof(indices) options:MTLResourceStorageModeShared];
    requireMaterial(_vertices && _quad && _indices,"UV meshes and indices");
    for (unsigned i=0;i<2;++i) {
        auto pixels=Materials::texture(i);
        MTLTextureDescriptor* desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:Materials::size height:Materials::size mipmapped:NO];
        desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead;
        _textures[i]=[device newTextureWithDescriptor:desc];requireMaterial(_textures[i]!=nil,"material texture");
        [_textures[i] replaceRegion:MTLRegionMake2D(0,0,Materials::size,Materials::size) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:Materials::size*4];
    }
    MTLSamplerDescriptor* sampling=[MTLSamplerDescriptor new];
    sampling.normalizedCoordinates=YES;sampling.sAddressMode=MTLSamplerAddressModeRepeat;sampling.tAddressMode=MTLSamplerAddressModeRepeat;
    sampling.minFilter=MTLSamplerMinMagFilterLinear;sampling.magFilter=MTLSamplerMinMagFilterLinear;
    _linear=[device newSamplerStateWithDescriptor:sampling];
    sampling.minFilter=MTLSamplerMinMagFilterNearest;sampling.magFilter=MTLSamplerMinMagFilterNearest;
    _nearest=[device newSamplerStateWithDescriptor:sampling];requireMaterial(_linear && _nearest,"linear and nearest samplers");
    MTLDepthStencilDescriptor* depth=[MTLDepthStencilDescriptor new];
    depth.depthCompareFunction=MTLCompareFunctionLess;depth.depthWriteEnabled=YES;_depthState=[device newDepthStencilStateWithDescriptor:depth];
    depth.depthCompareFunction=MTLCompareFunctionAlways;depth.depthWriteEnabled=NO;_flatState=[device newDepthStencilStateWithDescriptor:depth];
    requireMaterial(_depthState && _flatState,"material depth states");
    [depth release];[sampling release];[pipeline release];[vertex release];[fragment release];[library release];
    return self;
}
- (id<MTLRenderCommandEncoder>)begin: (id<MTLCommandBuffer>)command target: (id<MTLTexture>)target {
    if (!_depth || _depth.width!=target.width || _depth.height!=target.height) {
        MTLTextureDescriptor* desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:target.width height:target.height mipmapped:NO];
        desc.storageMode=MTLStorageModePrivate;desc.usage=MTLTextureUsageRenderTarget;
        id<MTLTexture> replacement=[_device newTextureWithDescriptor:desc];requireMaterial(replacement!=nil,"material depth texture");
        [_depth release];_depth=replacement;
    }
    MTLRenderPassDescriptor* pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.colorAttachments[0].clearColor=MTLClearColor{.04,.06,.10,1};
    pass.depthAttachment.texture=_depth;pass.depthAttachment.loadAction=MTLLoadActionClear;
    pass.depthAttachment.storeAction=MTLStoreActionDontCare;pass.depthAttachment.clearDepth=1;
    id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];requireMaterial(encoder!=nil,"material encoder");
    [encoder setRenderPipelineState:_pipeline];[encoder setCullMode:MTLCullModeNone];
    const Cube::Float4 tint {1,1,1,1};
    [encoder setFragmentBytes:&tint length:sizeof(tint) atIndex:6];
    return encoder;
}
- (void)quad: (id<MTLRenderCommandEncoder>)encoder width: (NSUInteger)width height: (NSUInteger)height {
    auto uniforms=Cube::uniforms(width,height,0);uniforms.animation.z=1;
    [encoder setDepthStencilState:_flatState];[encoder setVertexBuffer:_quad offset:0 atIndex:3];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:7];
    [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:6 indexType:MTLIndexTypeUInt16 indexBuffer:_indices indexBufferOffset:0];
}
- (void)encode: (id<MTLCommandBuffer>)command texture: (id<MTLTexture>)target time: (float)time {
    auto area=layout(target.width,target.height);
    id<MTLRenderCommandEncoder> encoder=[self begin:command target:target];
    [encoder setFragmentTexture:_textures[_selection] atIndex:2];[encoder setFragmentSamplerState:_linear atIndex:4];
    [encoder setViewport:MTLViewport{double(area.left),double(area.top),double(area.side),double(area.side),0,1}];
    [self quad:encoder width:area.side height:area.side];
    [encoder setViewport:MTLViewport{double(area.right),0,double(target.width-area.right),double(target.height),0,1}];
    auto uniforms=Cube::uniforms(target.width-area.right,target.height,time);
    [encoder setDepthStencilState:_depthState];[encoder setVertexBuffer:_vertices offset:0 atIndex:3];
    [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:7];
    [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:36 indexType:MTLIndexTypeUInt16 indexBuffer:_indices indexBufferOffset:0];
    [encoder endEncoding];
}
- (void)verifyOffscreen: (const char*)path {
    // Public-API sampling fixture: asymmetrical corners reveal flips and wrong slots.
    const unsigned char corners[]={255,0,0,255,0,255,0,255,0,0,255,255,255,255,0,255};
    MTLTextureDescriptor* small=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:2 mipmapped:NO];
    small.storageMode=MTLStorageModeShared;small.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> source=[_device newTextureWithDescriptor:small];requireMaterial(source!=nil,"2x2 source");
    [source replaceRegion:MTLRegionMake2D(0,0,2,2) mipmapLevel:0 withBytes:corners bytesPerRow:8];
    for (unsigned mode=0;mode<2;++mode) {
        unsigned side=mode?1:16;
        MTLTextureDescriptor* desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:side height:side mipmapped:NO];
        desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageRenderTarget;
        id<MTLTexture> target=[_device newTextureWithDescriptor:desc];requireMaterial(target!=nil,"sampling target");
        id<MTLCommandBuffer> command=[_queue commandBuffer];id<MTLRenderCommandEncoder> encoder=[self begin:command target:target];
        [encoder setViewport:MTLViewport{0,0,double(side),double(side),0,1}];
        [encoder setFragmentTexture:source atIndex:2];[encoder setFragmentSamplerState:mode?_linear:_nearest atIndex:4];
        [self quad:encoder width:side height:side];[encoder endEncoding];[command commit];[command waitUntilCompleted];
        std::vector<unsigned char> pixels(side*side*4);
        [target getBytes:pixels.data() bytesPerRow:side*4 fromRegion:MTLRegionMake2D(0,0,side,side) mipmapLevel:0];
        for (unsigned y=0;y<side;++y) for (unsigned x=0;x<side;++x) {
            unsigned corner=(y>=8?2:0)+(x>=8?1:0);
            const int mean[]={128,128,64,255};
            for (unsigned c=0;c<4;++c) {
                unsigned rgba=c==0?2:c==2?0:c;
                requireMaterial(std::abs(int(pixels[(y*side+x)*4+c])-(mode?mean[rgba]:corners[corner*4+rgba]))<=1,"nearest orientation / linear center at texture 2 sampler 4");
            }
        }
        [target release];
    }
    [source release];std::printf("PASS texture upload, UV orientation, nearest and linear filtering at texture 2 / sampler 4\n");
    MTLTextureDescriptor* desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:800 height:500 mipmapped:NO];
    desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageRenderTarget;
    id<MTLTexture> target=[_device newTextureWithDescriptor:desc];requireMaterial(target!=nil,"material scene target");
    std::string stem(path);if (stem.size()>4 && stem.substr(stem.size()-4)==".ppm") stem.resize(stem.size()-4);
    for (unsigned frame=0;frame<4;++frame) {
        self.selection=frame%2;float time=frame<2?0:.8f;
        id<MTLCommandBuffer> command=[_queue commandBuffer];[self encode:command texture:target time:time];
        [command commit];[command waitUntilCompleted];requireMaterial(command.error==nil,"material completion");
        std::vector<unsigned char> pixels(800*500*4);
        [target getBytes:pixels.data() bytesPerRow:800*4 fromRegion:MTLRegionMake2D(0,0,800,500) mipmapLevel:0];
        FILE* file=std::fopen((stem+"-"+std::to_string(frame)+".ppm").c_str(),"wb");requireMaterial(file!=nullptr,"material image");
        std::fprintf(file,"P6\n800 500\n255\n");
        for (size_t i=0;i<800*500;++i) { unsigned char rgb[]={pixels[i*4+2],pixels[i*4+1],pixels[i*4]};requireMaterial(std::fwrite(rgb,1,3,file)==3,"image write"); }
        requireMaterial(std::fclose(file)==0,"image close");
        requireMaterial(validate(pixels,800,500,time,_selection)==0,"preview and perspective-correct cube UV match CPU sampling");
        requireMaterial(validate(pixels,800,500,time,1-_selection)>1000,"negative control rejects the other material");

    }
    [target release];self.selection=0;std::printf("PASS concrete/wood switching, flat preview and cube UV at two rotation times\n");
}
- (void)dealloc {
    for (id<MTLTexture> texture:_textures) [texture release];
    [_depth release];[_linear release];[_nearest release];[_depthState release];[_flatState release];
    [_vertices release];[_quad release];[_indices release];[_pipeline release];[_queue release];[_device release];
    [super dealloc];
}
@end
