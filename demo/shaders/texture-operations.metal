// SPDX-License-Identifier: GPL-3.0-or-later
#include <metal_stdlib>
using namespace metal;
kernel void upload_pixels(const device float4* pixels [[buffer(5)]],
                          constant uint4& extent [[buffer(7)]],
                          texture2d<float,access::write> destination [[texture(3)]],
                          uint2 p [[thread_position_in_grid]]) {
    if (p.x<extent.x && p.y<extent.y) destination.write(pixels[p.y*extent.x+p.x],p);
}
kernel void read_pixels(texture2d<float,access::read> image [[texture(3)]],
                        device float4* output [[buffer(5)]],
                        constant uint4& extent [[buffer(7)]],
                        uint2 p [[thread_position_in_grid]]) {
    if (p.x<extent.x && p.y<extent.y) output[p.y*extent.x+p.x]=image.read(p);
}

kernel void modify_pixels(texture2d<float,access::read_write> image [[texture(3)]],uint2 p [[thread_position_in_grid]]) {
    if (p.x<image.get_width() && p.y<image.get_height()) {
        float4 value=image.read(p);image.write(float4(value.z,value.y,value.x,value.w),p);
    }
}
