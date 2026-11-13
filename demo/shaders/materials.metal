// SPDX-License-Identifier: GPL-3.0-or-later
#include <metal_stdlib>
using namespace metal;
struct MaterialVertex { float4 position; float4 detail; };
struct MaterialUniforms { float4 projection; float4 animation; };
struct MaterialOutput { float4 position [[position]]; float2 uv; float shade; };

vertex MaterialOutput material_vertex(const device MaterialVertex* vertices [[buffer(3)]],
                                     constant MaterialUniforms& uniforms [[buffer(7)]],
                                     uint index [[vertex_id]]) {
    float4 p=vertices[index].position;
    MaterialOutput result;
    result.position=p;
    if (uniforms.animation.z < 0.5f) {
        float yaw=.55f+uniforms.animation.x*.63f;
        float pitch=.35f+uniforms.animation.x*.37f;
        float cy=cos(yaw),sy=sin(yaw),cx=cos(pitch),sx=sin(pitch);
        float x=cy*p.x+sy*p.z;
        float z=-sy*p.x+cy*p.z;
        float y=cx*p.y-sx*z;
        float depth=uniforms.animation.y-(sx*p.y+cx*z);
        result.position=float4(x*uniforms.projection.y/uniforms.projection.x,y*uniforms.projection.y,
            uniforms.projection.w*(depth-uniforms.projection.z)/(uniforms.projection.w-uniforms.projection.z),depth);
    }
    result.uv=vertices[index].detail.xy;
    result.shade=vertices[index].detail.z;
    return result;
}

fragment float4 material_fragment(MaterialOutput input [[stage_in]],
                                  constant float4& tint [[buffer(6)]],
                                  texture2d<float> surface [[texture(2)]],
                                  sampler filtering [[sampler(4)]]) {
    return surface.sample(filtering,input.uv)*float4(input.shade,input.shade,input.shade,1.0f)*tint;
}
