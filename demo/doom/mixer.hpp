// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <vector>

namespace DoomAudio {
constexpr unsigned rate=44100;
struct Sample { unsigned rate=0;std::vector<uint8_t> pcm; };
inline unsigned le16(const uint8_t* p) { return p[0]|unsigned(p[1])<<8; }
inline uint32_t le32(const uint8_t* p) { return le16(p)|uint32_t(le16(p+2))<<16; }
// DMX digital effect lump: format 3, sample rate, byte count, unsigned PCM.
// Bounds are checked before copying bytes from an untrusted WAD lump.
inline Sample decode(const uint8_t* data,size_t size) {
    Sample sample;
    if (!data || size<8 || le16(data)!=3) return sample;
    unsigned hz=le16(data+2);uint32_t count=le32(data+4);
    if (hz<1000 || hz>192000 || count>size-8 || count<=32) return sample;
    sample.rate=hz;
    // The format reserves 16 guard samples at each end.
    sample.pcm.assign(data+24,data+8+count-16);return sample;
}
struct Channel {
    const Sample* sample=nullptr;
    uint64_t position=0;
    unsigned volume=0,separation=127;
};
class Mixer {
public:
    std::array<Channel,16> channels{};
    void render(int16_t* output,size_t frames) {
        for (size_t frame=0;frame<frames;++frame) {
            int left=0,right=0;
            for (auto& c:channels) {
                if (!c.sample) continue;
                size_t index=c.position>>32;
                if (index>=c.sample->pcm.size()) {c.sample=nullptr;continue;}
                int amplitude=(int(c.sample->pcm[index])-128)*256;
                left+=amplitude*int(c.volume)*int(254-c.separation)/(127*254);
                right+=amplitude*int(c.volume)*int(c.separation)/(127*254);
                c.position+=(uint64_t(c.sample->rate)<<32)/rate;
            }
            output[frame*2]=std::clamp(left,-32768,32767);
            output[frame*2+1]=std::clamp(right,-32768,32767);
        }
    }
};
}
