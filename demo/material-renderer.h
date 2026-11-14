// SPDX-License-Identifier: GPL-3.0-or-later
#import <Metal/Metal.h>
@class TextureOperations;
@interface MaterialRenderer : NSObject {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline, _embeddedPipeline;
    id<MTLBuffer> _vertices, _quad, _indices;
    id<MTLTexture> _textures[2], _depth;
    id<MTLSamplerState> _linear, _nearest;
    id<MTLDepthStencilState> _depthState, _flatState;
    NSUInteger _selection;
    BOOL _lightingEnabled, _embeddedSamplingEnabled;
    TextureOperations* _operations;
}
@property(nonatomic) NSUInteger selection;
@property(nonatomic) BOOL lightingEnabled;
- (instancetype)initWithDevice: (id<MTLDevice>)device queue: (id<MTLCommandQueue>)queue;
- (void)encode: (id<MTLCommandBuffer>)command texture: (id<MTLTexture>)texture time: (float)time;
- (void)verifyOffscreen: (const char*)path;
@end
