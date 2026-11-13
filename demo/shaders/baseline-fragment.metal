// SPDX-License-Identifier: GPL-3.0-or-later
#include <metal_stdlib>
using namespace metal;

fragment float4 baseline_fragment() {
    return float4(0.2f, 0.6f, 1.0f, 1.0f);
}
