// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace Shapes {
constexpr float pi = 3.14159265358979323846f;
constexpr unsigned segments = 96;
constexpr float innerRadius = 0.72f;
struct alignas(16) Float4 { float x, y, z, w; };
struct Uniforms { Float4 layout, tint, frame; };
static_assert(sizeof(Float4) == 16 && sizeof(Uniforms) == 48, "MSL float4 layout");
struct Object { Uniforms uniforms; unsigned kind; };

inline std::vector<Float4> geometry(unsigned kind) {
    if (kind == 0)
        return {{-1,-1,0,1}, {1,-1,0,1}, {-1,1,0,1},
                {-1,1,0,1}, {1,-1,0,1}, {1,1,0,1}};
    std::vector<Float4> vertices;
    for (unsigned i = 0; i < segments; ++i) {
        float a = 2 * pi * i / segments, b = 2 * pi * (i + 1) / segments;
        Float4 p {std::cos(a), std::sin(a), 0, 1};
        Float4 q {std::cos(b), std::sin(b), 0, 1};
        if (kind == 1) {
            vertices.insert(vertices.end(), {{0,0,0,1}, p, q});
        } else {
            Float4 ip {p.x * innerRadius, p.y * innerRadius, 0, 1};
            Float4 iq {q.x * innerRadius, q.y * innerRadius, 0, 1};
            vertices.insert(vertices.end(), {p, q, ip, ip, q, iq});
        }
    }
    return vertices;
}

inline std::array<Object, 3> scene(float width, float height, float time) {
    std::array<Object, 3> objects {};
    const float base = std::min(width * 0.09f, height * 0.18f);
    for (unsigned i = 0; i < objects.size(); ++i) {
        float phase = i * 1.7f;
        float size = base * (i == 0 ? 0.72f : i == 1 ? 0.88f : 1.0f);
        size *= 1 + 0.14f * std::sin(time * 1.4f + phase);
        float x = width * (0.22f + i * 0.28f) + width * 0.028f * std::sin(time * 0.8f + phase);
        float y = height * (0.5f + 0.07f * std::sin(time * 1.1f + phase));
        const Float4 colors[] = {{1.0f,0.48f,0.2f,1}, {0.2f,0.72f,1.0f,1}, {0.75f,0.38f,1.0f,1}};
        Float4 color = colors[i];
        color.x = std::clamp(color.x + 0.16f * std::sin(time * 0.9f + phase), 0.05f, 1.0f);
        color.y = std::clamp(color.y + 0.14f * std::sin(time * 0.7f + phase), 0.05f, 1.0f);
        objects[i] = {{{x,y,size,i == 0 ? 0.65f : -0.25f}, color,
                       {width,height,time,0.15f}}, i};
    }
    return objects;
}

// Analytic reference in pixel coordinates, independent of the triangle mesh.
// Positive distance denotes the shape's interior; the ring's hole is outside.
inline float interiorDistance(const Object& object, float x, float y) {
    const auto& u = object.uniforms;
    float dx = x - u.layout.x, dy = y - u.layout.y;
    if (object.kind == 0) {
        float angle = u.frame.w + u.frame.z * u.layout.w;
        float c = std::cos(angle), s = std::sin(angle);
        float lx = dx * c + dy * s, ly = -dx * s + dy * c;
        return std::min(u.layout.z - std::abs(lx), u.layout.z - std::abs(ly));
    }
    float radius = std::hypot(dx, dy);
    float distance = u.layout.z - radius;
    return object.kind == 1 ? distance : std::min(distance, radius - u.layout.z * innerRadius);
}
}
