// SPDX-License-Identifier: MPL-2.0
#pragma once
#import <Metal/MTLLibrary.h>
#if DARLING_METAL_ENABLED
#include <indium/device.hpp>
__attribute__((visibility("hidden")))
id<MTLLibrary> MTLCompileSourceLibrary(std::shared_ptr<Indium::Device> device,
    id<MTLDevice> owner, NSString* source, NSError** error);
#endif
