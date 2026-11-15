// SPDX-License-Identifier: GPL-3.0-or-later
#include "mixer.hpp"
#include <cassert>
#include <cstdio>
int main() {
    using namespace DoomAudio;
    assert(decode(nullptr,0).pcm.empty());
    std::vector<uint8_t> lump(8+36,128);
    lump[0]=3;lump[1]=0;lump[2]=0x44;lump[3]=0xac;
    lump[4]=36;lump[5]=lump[6]=lump[7]=0;
    lump[24]=255;lump[25]=0;lump[26]=255;lump[27]=0;
    Sample sample=decode(lump.data(),lump.size());assert(sample.rate==44100 && sample.pcm.size()==4);
    assert(decode(lump.data(),lump.size()-1).pcm.empty());
    lump[0]=4;assert(decode(lump.data(),lump.size()).pcm.empty());lump[0]=3;
    lump[7]=1;assert(decode(lump.data(),lump.size()).pcm.empty());lump[7]=0;
    Mixer mixer;int16_t pcm[12]{};
    mixer.channels[0]={&sample,0,127,0};mixer.render(pcm,6);
    assert(pcm[0]>32000 && pcm[1]==0 && pcm[2]==-32768);
    assert(pcm[8]==0 && !mixer.channels[0].sample);
    mixer.channels[0]={&sample,0,127,254};mixer.render(pcm,1);assert(pcm[0]==0 && pcm[1]>32000);
    for (auto& c:mixer.channels) c={&sample,0,127,0};
    mixer.render(pcm,2);assert(pcm[0]==32767 && pcm[2]==-32768);
    sample.rate=22050;mixer={};mixer.channels[0]={&sample,0,127,127};mixer.render(pcm,4);
    assert(pcm[0]==pcm[2] && pcm[4]==pcm[6] && pcm[0]>0 && pcm[4]<0);
    std::puts("PASS DMX bounds, invalid format, stereo separation, saturation, resampling, voice completion");
}
