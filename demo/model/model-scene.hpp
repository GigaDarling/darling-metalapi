// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "model-format.hpp"
#include <algorithm>

namespace Model {
struct Scene { Float4 angles,projection,camera; };
struct Surface {Float4 base,properties,emissive,debug;};
static_assert(sizeof(Scene)==48 && sizeof(Surface)==64,"MSL uniform layouts");
inline Scene scene(unsigned width,unsigned height,float yaw,float pitch,float distance,unsigned mode) {
    return {{std::cos(yaw),std::sin(yaw),std::cos(pitch),std::sin(pitch)},
        {float(width)/height,1.9209821f,.05f,100.f},{distance,0,float(mode),0}};
}
inline Float4 debugColor(unsigned material) {
    return {float(53+material*67%180)/255,float(61+material*47%174)/255,float(73+material*31%166)/255,1};
}
struct Vec3 {float x,y,z;};
inline Vec3 sub(Vec3 a,Vec3 b) {return {a.x-b.x,a.y-b.y,a.z-b.z};}
inline Vec3 cross(Vec3 a,Vec3 b) {return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline float dot(Vec3 a,Vec3 b) {return a.x*b.x+a.y*b.y+a.z*b.z;}
inline Vec3 inverseRotation(Vec3 p,float yaw,float pitch) {
    float y=std::cos(pitch)*p.y+std::sin(pitch)*p.z,z=-std::sin(pitch)*p.y+std::cos(pitch)*p.z;
    return {std::cos(yaw)*p.x-std::sin(yaw)*z,y,std::sin(yaw)*p.x+std::cos(yaw)*z};
}
struct Hit {int material=-1;float margin=0;};
// Independent ray/triangle oracle for the viewer's flat material-ID test mode.
inline Hit trace(const Asset& asset,unsigned px,unsigned py,unsigned width,unsigned height,float yaw,float pitch,float distance) {
    Vec3 origin=inverseRotation({0,0,distance},yaw,pitch);
    Vec3 direction=inverseRotation({(2*(px+.5f)/width-1)*(float(width)/height)/1.9209821f,
        (1-2*(py+.5f)/height)/1.9209821f,-1},yaw,pitch);
    Hit hit;float nearest=1e30f;
    for (const auto& primitive:asset.primitives) for (uint32_t i=primitive.first;i<primitive.first+primitive.count;i+=3) {
        auto position=[&](uint32_t index) {auto p=asset.vertices[asset.indices[index]].position;return Vec3{p.x,p.y,p.z};};
        Vec3 a=position(i),e1=sub(position(i+1),a),e2=sub(position(i+2),a),p=cross(direction,e2);
        float determinant=dot(e1,p);if (std::abs(determinant)<1e-9f) continue;
        Vec3 t=sub(origin,a);float u=dot(t,p)/determinant;if (u<0 || u>1) continue;
        Vec3 q=cross(t,e1);float v=dot(direction,q)/determinant;if (v<0 || u+v>1) continue;
        float depth=dot(e2,q)/determinant;
        if (depth>.05f && depth<nearest) {nearest=depth;hit={int(primitive.material),std::min({u,v,1-u-v})};}
    }
    return hit;
}
}
