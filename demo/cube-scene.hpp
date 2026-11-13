// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <cmath>
#include <cstdint>

namespace Cube {
struct alignas(16) Float4 { float x, y, z, w; };
struct Vertex { Float4 position, color; };
struct Uniforms { Float4 projection, animation; };
static_assert(sizeof(Vertex) == 32 && sizeof(Uniforms) == 32, "MSL float4 layout");
constexpr float cameraDistance = 4.8f;
constexpr float focalScale = 1.9209821f; // cot(55 degrees / 2)
constexpr std::array<Float4, 6> colors {{
    {0.12f,0.75f,0.95f,1}, {0.95f,0.22f,0.28f,1},
    {1.0f,0.48f,0.16f,1}, {0.72f,0.28f,0.98f,1},
    {0.42f,0.92f,0.46f,1}, {0.24f,0.38f,0.96f,1}
}};

inline std::array<Vertex, 24> vertices() {
    const Float4 faces[6][4] = {
        {{-1,-1,1,1},{1,-1,1,1},{1,1,1,1},{-1,1,1,1}},
        {{1,-1,-1,1},{-1,-1,-1,1},{-1,1,-1,1},{1,1,-1,1}},
        {{1,-1,1,1},{1,-1,-1,1},{1,1,-1,1},{1,1,1,1}},
        {{-1,-1,-1,1},{-1,-1,1,1},{-1,1,1,1},{-1,1,-1,1}},
        {{-1,1,1,1},{1,1,1,1},{1,1,-1,1},{-1,1,-1,1}},
        {{-1,-1,-1,1},{1,-1,-1,1},{1,-1,1,1},{-1,-1,1,1}}
    };
    std::array<Vertex, 24> result {};
    for (unsigned face = 0; face < 6; ++face)
        for (unsigned corner = 0; corner < 4; ++corner)
            result[face * 4 + corner] = {faces[face][corner], colors[face]};
    return result;
}

inline std::array<uint16_t, 36> indices() {
    std::array<uint16_t, 36> result {};
    const unsigned corners[] = {0,1,2,0,2,3};
    for (unsigned face = 0; face < 6; ++face)
        for (unsigned i = 0; i < 6; ++i)
            result[face * 6 + i] = face * 4 + corners[i];
    return result;
}

inline Uniforms uniforms(unsigned width, unsigned height, float time) {
    return {{float(width) / height, focalScale, 0.1f, 100.0f}, {time,cameraDistance,0,0}};
}
}
