// SPDX-License-Identifier: GPL-3.0-or-later
#include <metal_stdlib>
using namespace metal;
struct Vertex { float4 position;float4 normal;float4 uv;float4 tangent; };
struct Scene { float4 angles;float4 projection;float4 camera; };
struct Material {float4 base;float4 properties;float4 emissive;float4 debug;};
struct Output {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float4 tangent;
    float2 uv;
};
float3 rotatePoint(float3 p,float4 angles) {
    float x=angles.x*p.x+angles.y*p.z;
    float z=-angles.y*p.x+angles.x*p.z;
    return float3(x,angles.z*p.y-angles.w*z,angles.w*p.y+angles.z*z);
}
vertex Output model_vertex(const device Vertex* vertices [[buffer(3)]],constant Scene& scene [[buffer(7)]],uint index [[vertex_id]]) {
    Vertex v=vertices[index];Output result;
    float3 p=rotatePoint(v.position.xyz,scene.angles);
    float depth=scene.camera.x-p.z;
    result.position=float4(p.x*scene.projection.y/scene.projection.x,p.y*scene.projection.y,
        scene.projection.w*(depth-scene.projection.z)/(scene.projection.w-scene.projection.z),depth);
    result.world=p;result.normal=rotatePoint(v.normal.xyz,scene.angles);
    result.tangent=float4(rotatePoint(v.tangent.xyz,scene.angles),v.tangent.w);result.uv=v.uv.xy;
    return result;
}
fragment float4 model_fragment(Output input [[stage_in]],constant Scene& scene [[buffer(7)]],constant Material& material [[buffer(6)]],
    texture2d<float> baseMap [[texture(0)]],texture2d<float> normalMap [[texture(1)]],
    texture2d<float> ormMap [[texture(2)]],texture2d<float> occlusionMap [[texture(3)]],texture2d<float> emissiveMap [[texture(4)]]) {
    constexpr sampler filtering(coord::normalized,address::repeat,filter::linear);
    float3 base=pow(baseMap.sample(filtering,input.uv).rgb,float3(2.2f))*material.base.rgb;
    if (scene.camera.z>2.5f) return material.debug;
    if (scene.camera.z>0.5f && scene.camera.z<1.5f) return float4(pow(base,float3(1.0f/2.2f)),1);
    float3 n=normalize(input.normal);
    float3 tangent=normalize(input.tangent.xyz-n*dot(n,input.tangent.xyz));
    float3 bitangent=cross(n,tangent)*input.tangent.w;
    float3 mapped=normalMap.sample(filtering,input.uv).xyz*2.0f-1.0f;
    mapped.xy*=material.properties.z;
    n=normalize(tangent*mapped.x+bitangent*mapped.y+n*mapped.z);
    if (scene.camera.z>1.5f) return float4(n*.5f+.5f,1);
    float3 packed=ormMap.sample(filtering,input.uv).rgb;
    float roughness=clamp(packed.g*material.properties.y,.06f,1.0f);
    float metallic=clamp(packed.b*material.properties.x,0.0f,1.0f);
    float ao=1.0f-material.properties.w*(1.0f-occlusionMap.sample(filtering,input.uv).r);
    float3 view=normalize(float3(0,0,scene.camera.x)-input.world);
    float3 light=normalize(float3(-2.8f,3.8f,4.5f)-input.world);
    float3 halfVector=normalize(light+view);
    float nl=max(dot(n,light),0.0f),nv=max(dot(n,view),.001f),nh=max(dot(n,halfVector),0.0f),vh=max(dot(view,halfVector),0.0f);
    float alpha=roughness*roughness,alpha2=alpha*alpha;
    float denominator=nh*nh*(alpha2-1.0f)+1.0f;
    float distribution=alpha2/(3.14159265f*denominator*denominator);
    float k=(roughness+1.0f)*(roughness+1.0f)/8.0f;
    float geometry=(nl/(nl*(1.0f-k)+k))*(nv/(nv*(1.0f-k)+k));
    float3 f0=mix(float3(.04f),base,metallic);
    float3 fresnel=f0+(1.0f-f0)*pow(1.0f-vh,5.0f);
    float3 specular=distribution*geometry*fresnel/max(4.0f*nl*nv,.001f);
    float3 diffuse=(1.0f-fresnel)*(1.0f-metallic)*base/3.14159265f;
    float3 fill=normalize(float3(3,1.5f,-2));
    float fillAmount=max(dot(n,fill),0.0f);
    float3 color=(diffuse+specular)*nl*4.0f+(base*.28f+f0*.12f)*ao+base*fillAmount*.18f;
    color+=pow(emissiveMap.sample(filtering,input.uv).rgb,float3(2.2f))*material.emissive.rgb;
    color=color/(color+1.0f);
    return float4(pow(max(color,float3(0)),float3(1.0f/2.2f)),1);
}
