// SPDX-License-Identifier: GPL-3.0-or-later
#import <Metal/Metal.h>
#include "model-format.hpp"
@interface ModelRenderer : NSObject {
    Model::Asset* _asset;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLDepthStencilState> _depthState;
    id<MTLBuffer> _vertices,_indices;
    id<MTLTexture> _depth;
    NSMutableArray* _textures;
    NSMutableArray* _fallback;
}
@property(nonatomic) float yaw;
@property(nonatomic) float pitch;
@property(nonatomic) float distance;
@property(nonatomic) unsigned mode;
@property(nonatomic,readonly) NSUInteger triangles;
@property(nonatomic,readonly) NSUInteger vertices;
@property(nonatomic,readonly) NSUInteger materials;
- (instancetype)initWithDevice:(id<MTLDevice>)device path:(const char*)path;
- (void)encode:(id<MTLCommandBuffer>)command texture:(id<MTLTexture>)texture reverse:(BOOL)reverse;
- (id<MTLCommandQueue>)queue;
- (void)verifyOffscreen:(const char*)path;
@end
