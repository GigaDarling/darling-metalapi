// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace AppleSample {
struct Result { size_t checked=0,mismatches=0,triangles=0; };
// Independent analytic triangle coverage, not a copy of the renderer's vertex
// update loop. Later triangles cover earlier ones; narrow edge bands are omitted.
inline Result validate(const std::vector<unsigned char>& pixels,unsigned width,unsigned height,float phase) {
    static const int rgb[][3]={{255,0,0},{0,255,0},{0,0,255},{255,0,255},{0,255,255},{255,255,0}};
    std::array<double,50> centers;
    for (int t=0;t<50;++t) centers[t]=128*std::sin((-400+t*16)/128.0+phase);
    Result result;
    for (unsigned y=1;y+1<height;y+=2) for (unsigned x=1;x+1<width;x+=2) {
        double sx=x+.5-width*.5,sy=height*.5-y-.5;
        int visible=-1;bool edge=false;
        for (int t=0;t<50;++t) {
            double center=-400+t*16,dx=sx-center,dy=sy-centers[t];
            double distance=std::min({dy+32,32-dy,(16-.5*dy-std::abs(dx))/std::sqrt(1.25)});
            if (std::abs(distance)<1.2) edge=true;
            if (distance>0) visible=t;
        }
        if (edge) continue;
        std::array<int,4> expected={20,13,10,255};
        if (visible>=0) { expected={rgb[visible%6][2],rgb[visible%6][1],rgb[visible%6][0],255};++result.triangles; }
        bool match=true;
        for (unsigned c=0;c<4;++c) if (std::abs(int(pixels[(size_t(y)*width+x)*4+c])-expected[c])>1) match=false;
        ++result.checked;result.mismatches+=!match;
    }
    return result;
}
}
