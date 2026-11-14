// SPDX-License-Identifier: GPL-3.0-or-later
#import <Metal/Metal.h>
@interface TextureOperations : NSObject {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLComputePipelineState> _write, _read, _modify;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device queue:(id<MTLCommandQueue>)queue;
- (void)uploadRGBA:(const unsigned char*)pixels width:(NSUInteger)width height:(NSUInteger)height toTexture:(id<MTLTexture>)texture;
- (void)verify;
@end
