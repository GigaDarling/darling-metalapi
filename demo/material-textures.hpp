// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace Materials {
constexpr unsigned size = 512;
inline float random(unsigned x, unsigned y, unsigned seed = 0) {
    uint32_t n = x * 374761393u + y * 668265263u + seed * 2246822519u;
    n = (n ^ (n >> 13)) * 1274126177u;
    return float(n ^ (n >> 16)) / 4294967295.0f;
}
inline float noise(float x, float y, unsigned seed) {
    unsigned ix = unsigned(x), iy = unsigned(y);
    float fx=x-ix, fy=y-iy;
    fx=fx*fx*(3-2*fx); fy=fy*fy*(3-2*fy);
    float a=random(ix,iy,seed), b=random(ix+1,iy,seed);
    float c=random(ix,iy+1,seed), d=random(ix+1,iy+1,seed);
    return (a+(b-a)*fx)*(1-fy)+(c+(d-c)*fx)*fy;
}
// Authored deterministic RGBA bitmaps. No third-party photos or assets are used.
inline std::vector<unsigned char> texture(unsigned material) {
    std::vector<unsigned char> pixels(size*size*4);
    for (unsigned y=0;y<size;++y) for (unsigned x=0;x<size;++x) {
        float r,g,b;
        if (material == 0) {
            float cloud=noise(x/60.0f,y/60.0f,7)-0.5f;
            float fine=random(x,y,8)-0.5f;
            float aggregate=noise(x/5.0f,y/5.0f,9)-0.5f;
            float value=0.56f+cloud*.17f+fine*.13f+aggregate*.14f;
            float pores=random(x/2,y/2,12);
            if (pores>.975f) value-=.20f*(pores-.975f)/.025f;
            r=value*1.02f;g=value;b=value*.96f;
        } else {
            unsigned board=x/128;
            float warp=11*std::sin(y*.012f)+5*std::sin(y*.031f+board);
            float grain=std::sin(x*.24f+warp+noise(x/32.0f,y/180.0f,3)*13);
            float fibers=std::sin(x*1.7f+warp*.5f)*.018f;
            float value=.64f+grain*.075f+fibers+(noise(x/22.0f,y/110.0f,4)-.5f)*.17f;
            value+=(random(board,0,20)-.5f)*.13f;
            float dx=(float(x%128)-65)/20,dy=(float(y)-float(90+board*95))/60;
            float knot=std::exp(-(dx*dx+dy*dy));
            value-=knot*(.12f+.06f*std::sin(std::sqrt(dx*dx+dy*dy)*32));
            if (x%128<2) value*=.52f;
            r=value;g=value*.67f;b=value*.36f;
        }
        size_t offset=(size_t(y)*size+x)*4;
        pixels[offset]=std::lround(std::clamp(r,0.f,1.f)*255);
        pixels[offset+1]=std::lround(std::clamp(g,0.f,1.f)*255);
        pixels[offset+2]=std::lround(std::clamp(b,0.f,1.f)*255);
        pixels[offset+3]=255;
    }
    return pixels;
}
}
