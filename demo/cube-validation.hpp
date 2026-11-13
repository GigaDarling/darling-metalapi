// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "cube-scene.hpp"
#include <algorithm>
#include <limits>
#include <vector>

namespace Cube {
// Independent reference: intersect camera rays with six planes of a unit box.
// It never reads the indexed mesh or emulates triangle rasterization.
inline int rayFace(float px, float py, unsigned width, unsigned height, float time,
                   std::array<double,3>* hit = nullptr) {
    const double yaw = 0.55 + double(time) * 0.63, pitch = 0.35 + double(time) * 0.37;
    const double cy = std::cos(yaw), sy = std::sin(yaw), cx = std::cos(pitch), sx = std::sin(pitch);
    auto inverseRotation = [&](std::array<double,3> p) {
        double y = cx * p[1] + sx * p[2], z = -sx * p[1] + cx * p[2];
        return std::array<double,3> {cy * p[0] - sy * z, y, sy * p[0] + cy * z};
    };
    auto origin = inverseRotation({0,0,cameraDistance});
    auto direction = inverseRotation({(2.0 * px / width - 1) * (double(width) / height) / focalScale,
                                      (1 - 2.0 * py / height) / focalScale, -1});
    double nearest = std::numeric_limits<double>::infinity();
    int face = -1;
    for (unsigned axis = 0; axis < 3; ++axis) {
        if (std::abs(direction[axis]) < 1e-12) continue;
        for (int side : {-1,1}) {
            double t = (side - origin[axis]) / direction[axis];
            if (t <= 0 || t >= nearest) continue;
            bool inside = true;
            for (unsigned other = 0; other < 3; ++other)
                if (other != axis && std::abs(origin[other] + t * direction[other]) > 1) inside = false;
            if (inside) {
                nearest = t;
                if (hit) for (unsigned i=0;i<3;++i) (*hit)[i]=origin[i]+t*direction[i];
                face = axis == 2 ? (side > 0 ? 0 : 1) : axis == 0 ? (side > 0 ? 2 : 3) : (side > 0 ? 4 : 5);
            }
        }
    }
    return face;
}

struct Validation { size_t checked = 0, mismatches = 0; std::array<size_t,6> faces {}; };
inline bool stablePixel(float px, float py, unsigned width, unsigned height, float time, int face) {
    return rayFace(px-1.5f,py,width,height,time) == face && rayFace(px+1.5f,py,width,height,time) == face &&
           rayFace(px,py-1.5f,width,height,time) == face && rayFace(px,py+1.5f,width,height,time) == face;
}

inline Validation validate(const std::vector<unsigned char>& pixels, unsigned width, unsigned height, float time) {
    Validation result;
    for (unsigned y = 0; y < height; ++y) for (unsigned x = 0; x < width; ++x) {
        float px = x + 0.5f, py = y + 0.5f;
        int face = rayFace(px,py,width,height,time);
        // Exclude only a narrow silhouette/face-edge band, where sample coverage is discrete.
        if (!stablePixel(px,py,width,height,time,face)) continue;
        Float4 color = face < 0 ? Float4 {0.04f,0.06f,0.10f,1} : colors[face];
        const int bgra[] = {int(std::lround(color.z * 255)),int(std::lround(color.y * 255)),
                            int(std::lround(color.x * 255)),255};
        bool matches = true;
        for (unsigned channel = 0; channel < 4; ++channel)
            if (std::abs(int(pixels[(size_t(y)*width+x)*4+channel]) - bgra[channel]) > (channel==3 ? 0 : 2)) matches = false;
        ++result.checked;
        result.mismatches += !matches;
        if (face >= 0) ++result.faces[face];
    }
    return result;
}
}
