// SPDX-License-Identifier: GPL-3.0-or-later
#include <metal_stdlib>
using namespace metal;

struct CubeVertex { float4 position; float4 color; };
struct CubeUniforms { float4 projection; float4 animation; };
struct CubeOutput { float4 position [[position]]; float4 color; };

vertex CubeOutput cube_vertex(const device CubeVertex* vertices [[buffer(3)]],
                              constant CubeUniforms& uniforms [[buffer(7)]],
                              uint index [[vertex_id]]) {
    float yaw = 0.55f + uniforms.animation.x * 0.63f;
    float pitch = 0.35f + uniforms.animation.x * 0.37f;
    float cy = cos(yaw), sy = sin(yaw);
    float cx = cos(pitch), sx = sin(pitch);
    float4 p = vertices[index].position;
    float x = cy * p.x + sy * p.z;
    float z = -sy * p.x + cy * p.z;
    float y = cx * p.y - sx * z;
    float depth = uniforms.animation.y - (sx * p.y + cx * z);
    float nearPlane = uniforms.projection.z;
    float farPlane = uniforms.projection.w;
    CubeOutput result;
    result.position = float4(x * uniforms.projection.y / uniforms.projection.x,
                            y * uniforms.projection.y,
                            farPlane * (depth - nearPlane) / (farPlane - nearPlane), depth);
    result.color = vertices[index].color;
    return result;
}

fragment float4 cube_fragment(CubeOutput input [[stage_in]]) {
    return input.color;
}
