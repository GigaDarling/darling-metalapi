// SPDX-License-Identifier: GPL-3.0-or-later
#import "renderer.h"
#include "model-scene.hpp"
#include <algorithm>
#include <cstdio>
#include <set>
#include <string>

static void requireModel(bool ok,const char* text) {
    if (!ok) throw std::runtime_error(text);
}
@implementation ModelRenderer
- (instancetype)initWithDevice:(id<MTLDevice>)device path:(const char*)path {
    self=[super init];if (!self) return nil;
    _asset=new Model::Asset(Model::load(path));_device=device;_queue=[device newCommandQueue];
    _yaw=.15f;_pitch=.12f;_distance=3.2f;
    NSError* error=nil;
    NSString* source=[NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"model" ofType:@"metal"]
        encoding:NSUTF8StringEncoding error:&error];
    requireModel(source!=nil,"cannot read bundled model shader");
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if (!library) std::fprintf(stderr,"Model shader: %s\n",error.description.UTF8String);
    requireModel(library!=nil,"model shader compilation failed");
    MTLRenderPipelineDescriptor* pipeline=[MTLRenderPipelineDescriptor new];
    pipeline.vertexFunction=[library newFunctionWithName:@"model_vertex"];
    pipeline.fragmentFunction=[library newFunctionWithName:@"model_fragment"];
    pipeline.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
    pipeline.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    _pipeline=[device newRenderPipelineStateWithDescriptor:pipeline error:&error];
    requireModel(_pipeline!=nil,"model pipeline creation failed");
    MTLDepthStencilDescriptor* depth=[MTLDepthStencilDescriptor new];
    depth.depthCompareFunction=MTLCompareFunctionLess;depth.depthWriteEnabled=YES;
    _depthState=[device newDepthStencilStateWithDescriptor:depth];
    _vertices=[device newBufferWithBytes:_asset->vertices.data() length:_asset->vertices.size()*sizeof(Model::Vertex) options:MTLResourceStorageModeShared];
    _indices=[device newBufferWithBytes:_asset->indices.data() length:_asset->indices.size()*4 options:MTLResourceStorageModeShared];
    requireModel(_queue && _depthState && _vertices && _indices,"model GPU resource allocation failed");
    _textures=[NSMutableArray new];_fallback=[NSMutableArray new];
    for (const auto& image:_asset->textures)
        [_textures addObject:[self texture:image.rgba.data() width:image.width height:image.height]];
    const unsigned char fallback[][4]={{255,255,255,255},{128,128,255,255},{255,255,255,255},{255,255,255,255},{255,255,255,255}};
    for (const auto& pixel:fallback) [_fallback addObject:[self texture:pixel width:1 height:1]];
    std::printf("MODEL: %zu vertices, %zu triangles, %zu primitives, %lu materials, %zu textures; device=%s\n",
        _asset->vertices.size(),_asset->indices.size()/3,_asset->primitives.size(),(unsigned long)self.materials,_asset->textures.size(),device.name.UTF8String);
    return self;
}
- (id<MTLTexture>)texture:(const unsigned char*)data width:(NSUInteger)width height:(NSUInteger)height {
    MTLTextureDescriptor* descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    descriptor.storageMode=MTLStorageModeShared;descriptor.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> texture=[_device newTextureWithDescriptor:descriptor];requireModel(texture!=nil,"model texture allocation failed");
    [texture replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:data bytesPerRow:width*4];
    return texture;
}
- (NSUInteger)vertices {return _asset->vertices.size();}
- (NSUInteger)triangles {return _asset->indices.size()/3;}
- (NSUInteger)materials {std::set<unsigned> used;for (auto p:_asset->primitives) used.insert(p.material);return used.size();}
- (id<MTLCommandQueue>)queue {return _queue;}
- (void)encode:(id<MTLCommandBuffer>)command texture:(id<MTLTexture>)texture reverse:(BOOL)reverse {
    if (!_depth || _depth.width!=texture.width || _depth.height!=texture.height) {
        MTLTextureDescriptor* descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:texture.width height:texture.height mipmapped:NO];
        descriptor.storageMode=MTLStorageModePrivate;descriptor.usage=MTLTextureUsageRenderTarget;
        _depth=[_device newTextureWithDescriptor:descriptor];requireModel(_depth!=nil,"model depth allocation failed");
    }
    MTLRenderPassDescriptor* pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=texture;pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.colorAttachments[0].clearColor=MTLClearColorMake(.026,.035,.055,1);
    pass.depthAttachment.texture=_depth;pass.depthAttachment.loadAction=MTLLoadActionClear;
    pass.depthAttachment.storeAction=MTLStoreActionDontCare;pass.depthAttachment.clearDepth=1;
    id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
    requireModel(encoder!=nil,"cannot create model render encoder");
    [encoder setRenderPipelineState:_pipeline];[encoder setDepthStencilState:_depthState];[encoder setCullMode:MTLCullModeNone];
    [encoder setViewport:MTLViewport{0,0,double(texture.width),double(texture.height),0,1}];
    auto scene=Model::scene(texture.width,texture.height,_yaw,_pitch,_distance,_mode);
    [encoder setVertexBuffer:_vertices offset:0 atIndex:3];
    [encoder setVertexBytes:&scene length:sizeof(scene) atIndex:7];
    [encoder setFragmentBytes:&scene length:sizeof(scene) atIndex:7];
    for (size_t i=0;i<_asset->primitives.size();++i) {
        const auto& primitive=_asset->primitives[reverse?_asset->primitives.size()-1-i:i];
        const auto& material=_asset->materials[primitive.material];
        Model::Surface surface{material.base,material.properties,material.emissive,Model::debugColor(primitive.material)};
        [encoder setFragmentBytes:&surface length:sizeof(surface) atIndex:6];
        for (unsigned slot=0;slot<5;++slot) {
            auto index=material.textures[slot];
            id<MTLTexture> image=index==Model::absent?[_fallback objectAtIndex:slot]:[_textures objectAtIndex:index];
            [encoder setFragmentTexture:image atIndex:slot];
        }
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:primitive.count indexType:MTLIndexTypeUInt32
            indexBuffer:_indices indexBufferOffset:size_t(primitive.first)*4];
    }
    [encoder endEncoding];
}
- (std::vector<unsigned char>)pixels:(id<MTLTexture>)target reverse:(BOOL)reverse {
    id<MTLCommandBuffer> command=[_queue commandBuffer];[self encode:command texture:target reverse:reverse];
    [command commit];[command waitUntilCompleted];requireModel(command.error==nil,"model GPU command failed");
    std::vector<unsigned char> pixels(target.width*target.height*4);
    [target getBytes:pixels.data() bytesPerRow:target.width*4 fromRegion:MTLRegionMake2D(0,0,target.width,target.height) mipmapLevel:0];
    return pixels;
}
- (void)verifyOffscreen:(const char*)path {
    std::string stem(path);if (stem.size()>4 && stem.substr(stem.size()-4)==".ppm") stem.resize(stem.size()-4);
    const unsigned sizes[][2]={{640,480},{640,480},{480,640}};
    std::vector<unsigned char> previous;
    for (unsigned frame=0;frame<3;++frame) {
        unsigned width=sizes[frame][0],height=sizes[frame][1];
        _yaw=.15f+frame*.7f;_pitch=.12f;_mode=0;
        MTLTextureDescriptor* descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
        descriptor.storageMode=MTLStorageModeShared;descriptor.usage=MTLTextureUsageRenderTarget;
        id<MTLTexture> target=[_device newTextureWithDescriptor:descriptor];requireModel(target!=nil,"offscreen model target failed");
        auto textured=[self pixels:target reverse:NO];
        if (frame==1) {size_t changed=0;for (size_t i=0;i<textured.size();++i) changed+=textured[i]!=previous[i];requireModel(changed>10000,"rotation does not change model pixels");}
        previous=textured;
        FILE* output=std::fopen((stem+"-"+std::to_string(frame)+".ppm").c_str(),"wb");requireModel(output!=nullptr,"cannot write model image");
        std::fprintf(output,"P6\n%u %u\n255\n",width,height);
        for (size_t p=0;p<textured.size();p+=4) {unsigned char rgb[]={textured[p+2],textured[p+1],textured[p]};requireModel(std::fwrite(rgb,1,3,output)==3,"cannot write model image data");}
        requireModel(std::fclose(output)==0,"cannot finish model image");
        _mode=3;auto flat=[self pixels:target reverse:NO];auto reversed=[self pixels:target reverse:YES];
        size_t tested=0,hits=0,mismatches=0,orderErrors=0,blankErrors=0;std::set<int> visible;
        for (unsigned y=9;y+9<height;y+=23) for (unsigned x=9;x+9<width;x+=23) {
            auto hit=Model::trace(*_asset,x,y,width,height,_yaw,_pitch,_distance);
            if (hit.material>=0 && hit.margin<.04f) continue;
            auto color=hit.material<0?Model::Float4{.026f,.035f,.055f,1}:Model::debugColor(hit.material);
            int expected[]={int(std::lround(color.z*255)),int(std::lround(color.y*255)),int(std::lround(color.x*255)),255};
            size_t pixel=(size_t(y)*width+x)*4;bool match=true,order=true,blank=true;
            for (unsigned c=0;c<4;++c) {match&=std::abs(int(flat[pixel+c])-expected[c])<=1;order&=std::abs(int(reversed[pixel+c])-expected[c])<=1;blank&=std::abs(expected[c])<=1;}
            ++tested;mismatches+=!match;orderErrors+=!order;blankErrors+=!blank;
            if (hit.material>=0) {++hits;visible.insert(hit.material);}
        }
        std::printf("MODEL CHECK %ux%u yaw=%.2f rays=%zu hits=%zu materials=%zu mismatches=%zu reversed=%zu\n",
            width,height,_yaw,tested,hits,visible.size(),mismatches,orderErrors);
        requireModel(tested>200 && hits>20 && !mismatches && !orderErrors,"model pixels disagree with independent ray/triangle depth reference");
        requireModel(blankErrors>200,"blank-image negative control did not fail");
    }
    _mode=0;std::puts("PASS complex model: GPU geometry/depth, uint32 indices, materials, rotation, portrait resize and blank negative control");
}
- (void)dealloc {delete _asset;}
@end
