// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include "cube-scene.hpp"

namespace Materials {
struct Light { Cube::Float4 tint, position, parameters, color; };
static_assert(sizeof(Light)==64,"MSL light uniform layout");
inline Light light(float time,bool enabled) {
    return {{1,1,1,1},{3.6f*std::cos(time*.9f),2.2f+.7f*std::sin(time*.7f),3.f+2.f*std::sin(time*.9f),1},
            {enabled?1.f:0.f,.20f,1.15f,.035f},{1.f,.94f,.84f,1}};
}
// CPU reference rotates the analytic box intersection and its outward normal.
inline std::array<double,3> illumination(std::array<double,3> point,int face,float rotation,float lightTime) {
    double yaw=.55+rotation*.63,pitch=.35+rotation*.37;
    auto rotate=[&](std::array<double,3> p) {
        double x=std::cos(yaw)*p[0]+std::sin(yaw)*p[2];
        double z=-std::sin(yaw)*p[0]+std::cos(yaw)*p[2];
        return std::array<double,3>{x,std::cos(pitch)*p[1]-std::sin(pitch)*z,std::sin(pitch)*p[1]+std::cos(pitch)*z};
    };
    const std::array<double,3> normals[]={{0,0,1},{0,0,-1},{1,0,0},{-1,0,0},{0,1,0},{0,-1,0}};
    auto position=rotate(point),normal=rotate(normals[face]);auto lamp=light(lightTime,true);
    double dx=lamp.position.x-position[0],dy=lamp.position.y-position[1],dz=lamp.position.z-position[2];
    double squared=dx*dx+dy*dy+dz*dz;
    double diffuse=std::max(0.0,(dx*normal[0]+dy*normal[1]+dz*normal[2])/std::sqrt(squared));
    double amount=lamp.parameters.y+lamp.parameters.z*diffuse/(1+lamp.parameters.w*squared);
    return {amount*lamp.color.x,amount*lamp.color.y,amount*lamp.color.z};
}
}
