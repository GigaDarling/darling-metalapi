// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "scene.hpp"
#include <cstdint>

namespace Shapes {
struct PixelCheck { size_t checked = 0, mismatches = 0; std::array<size_t, 3> interiors {}; };
inline PixelCheck validate(const std::vector<unsigned char>& pixels, unsigned width, unsigned height, float time) {
    auto objects = scene(width, height, time);
    PixelCheck result;
    for (unsigned y = 0; y < height; ++y) {
        for (unsigned x = 0; x < width; ++x) {
            int shape = -1;
            bool boundary = false;
            for (unsigned i = 0; i < objects.size(); ++i) {
                float d = interiorDistance(objects[i], x + 0.5f, y + 0.5f);
                // The analytic circles differ from their 96-segment meshes by
                // less than a pixel; compare every pixel away from those edges.
                if (std::abs(d) < 1.1f) boundary = true;
                if (d > 0) shape = i;
            }
            if (boundary) continue;
            unsigned char expected[] = {26, 15, 10, 255};
            if (shape >= 0) {
                const auto& c = objects[shape].uniforms.tint;
                expected[0] = std::lround(c.z * 255);
                expected[1] = std::lround(c.y * 255);
                expected[2] = std::lround(c.x * 255);
                ++result.interiors[shape];
            }
            bool match = true;
            for (unsigned channel = 0; channel < 4; ++channel)
                if (std::abs(int(pixels[(size_t(y) * width + x) * 4 + channel]) - expected[channel]) > 2)
                    match = false;
            ++result.checked;
            result.mismatches += !match;
        }
    }
    return result;
}
}
