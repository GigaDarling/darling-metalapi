// SPDX-License-Identifier: GPL-3.0-or-later
// Independently authored preparation fixture; no drawing is submitted by the probe.
#include <metal_stdlib>
using namespace metal;

struct BaselineVertex {
    float4 position [[position]];
};

vertex BaselineVertex baseline_vertex(uint vertexIndex [[vertex_id]]) {
    BaselineVertex result;
    float x = vertexIndex == 1u ? 0.5f : -0.5f;
    float y = vertexIndex == 2u ? 0.5f : -0.5f;
    result.position = float4(x, y, 0.0f, 1.0f);
    return result;
}
