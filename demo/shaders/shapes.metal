// SPDX-License-Identifier: GPL-3.0-or-later
#include <metal_stdlib>
using namespace metal;

struct ShapeUniforms {
    float4 layout; // center in pixels, radius/half-size, angular speed
    float4 tint;
    float4 frame;  // viewport size, elapsed seconds, initial angle
};

struct ShapeOutput {
    float4 position [[position]];
    float4 color;
};

vertex ShapeOutput shapes_vertex(const device float4* vertices [[buffer(3)]],
                                constant ShapeUniforms& uniforms [[buffer(7)]],
                                uint vertexIndex [[vertex_id]]) {
    float angle = uniforms.frame.w + uniforms.frame.z * uniforms.layout.w;
    float c = cos(angle);
    float s = sin(angle);
    float x = vertices[vertexIndex].x * uniforms.layout.z;
    float y = vertices[vertexIndex].y * uniforms.layout.z;
    float px = uniforms.layout.x + x * c - y * s;
    float py = uniforms.layout.y + x * s + y * c;
    ShapeOutput result;
    result.position = float4(px * 2.0f / uniforms.frame.x - 1.0f,
                            1.0f - py * 2.0f / uniforms.frame.y, 0.0f, 1.0f);
    result.color = uniforms.tint;
    return result;
}

fragment float4 shapes_fragment(ShapeOutput input [[stage_in]]) {
    return input.color;
}
