// SPDX-License-Identifier: GPL-3.0-or-later
#include <metal_stdlib>
using namespace metal;
struct MaterialVertex { float4 position; float4 detail; float4 normal; };
struct MaterialUniforms { float4 projection; float4 animation; };
struct LightUniforms { float4 tint; float4 position; float4 parameters; float4 color; };
struct MaterialOutput { float4 position [[position]]; float2 uv; float shade; float3 world; float3 normal; float lit; };
vertex MaterialOutput material_vertex(const device MaterialVertex* vertices [[buffer(3)]],
                                     constant MaterialUniforms& uniforms [[buffer(7)]],uint index [[vertex_id]]) {
    float4 p=vertices[index].position;
    float4 n=vertices[index].normal;
    MaterialOutput result;
    result.position=p;result.world=p.xyz;result.normal=n.xyz;result.lit=0.0f;
    if (uniforms.animation.z < 0.5f) {
        float yaw=.55f+uniforms.animation.x*.63f;
        float pitch=.35f+uniforms.animation.x*.37f;
        float cy=cos(yaw),sy=sin(yaw),cx=cos(pitch),sx=sin(pitch);
        float x=cy*p.x+sy*p.z,z=-sy*p.x+cy*p.z;
        float y=cx*p.y-sx*z,wz=sx*p.y+cx*z;
        float nx=cy*n.x+sy*n.z,nz=-sy*n.x+cy*n.z;
        result.world=float3(x,y,wz);
        result.normal=float3(nx,cx*n.y-sx*nz,sx*n.y+cx*nz);
        result.lit=1.0f;
        float depth=uniforms.animation.y-wz;
        result.position=float4(x*uniforms.projection.y/uniforms.projection.x,y*uniforms.projection.y,
            uniforms.projection.w*(depth-uniforms.projection.z)/(uniforms.projection.w-uniforms.projection.z),depth);
    }
    result.uv=vertices[index].detail.xy;result.shade=vertices[index].detail.z;
    return result;
}
fragment float4 material_fragment(MaterialOutput input [[stage_in]],
    constant LightUniforms& light [[buffer(6)]],texture2d<float> surface [[texture(2)]],sampler filtering [[sampler(4)]]) {
    float4 pixel=surface.sample(filtering,input.uv);
    if (light.parameters.x > 0.5f && input.lit > 0.5f) {
        float3 delta=light.position.xyz-input.world;
        float distance2=max(dot(delta,delta),.0001f);
        float diffuse=max(dot(normalize(input.normal),delta*rsqrt(distance2)),0.0f);
        float amount=light.parameters.y+light.parameters.z*diffuse/(1.0f+light.parameters.w*distance2);
        return float4(pixel.xyz*light.color.xyz*amount,pixel.w)*light.tint;
    }
    return pixel*float4(input.shade,input.shade,input.shade,1.0f)*light.tint;
}
fragment float4 material_embedded_fragment(MaterialOutput input [[stage_in]],
    constant LightUniforms& light [[buffer(6)]],texture2d<float> surface [[texture(2)]]) {
    constexpr sampler filtering(coord::normalized,address::repeat,filter::linear);
    float4 pixel=surface.sample(filtering,input.uv);
    if (light.parameters.x > 0.5f && input.lit > 0.5f) {
        float3 delta=light.position.xyz-input.world;
        float distance2=max(dot(delta,delta),.0001f);
        float diffuse=max(dot(normalize(input.normal),delta*rsqrt(distance2)),0.0f);
        float amount=light.parameters.y+light.parameters.z*diffuse/(1.0f+light.parameters.w*distance2);
        return float4(pixel.xyz*light.color.xyz*amount,pixel.w)*light.tint;
    }
    return pixel*float4(input.shade,input.shade,input.shade,1.0f)*light.tint;
}
