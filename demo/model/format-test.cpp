// SPDX-License-Identifier: GPL-3.0-or-later
#include "model-format.hpp"
#include <cassert>
#include <functional>
#include <string>

using Bytes=std::vector<unsigned char>;
static void integer(Bytes& b,uint32_t n) {for (unsigned s=0;s<32;s+=8)b.push_back(n>>s);}
static void number(Bytes& b,float n) {uint32_t bits;std::memcpy(&bits,&n,4);integer(b,bits);}
static void overwrite(Bytes& b,size_t offset,uint32_t n) {for(unsigned s=0;s<32;s+=8)b.at(offset+s/8)=n>>s;}
static Bytes triangle() {
    Bytes b={'D','M','O','D','E','L','1',0};for(auto n:{3,3,1,1,0})integer(b,n);
    for(unsigned v=0;v<3;++v)for(float n:{float(v==1),float(v==2),0.f,1.f,0.f,0.f,1.f,0.f,0.f,0.f,0.f,0.f,1.f,0.f,0.f,1.f})number(b,n);
    for(auto n:{0,1,2,0,3,0,0})integer(b,n);
    for(float n:{1.f,1.f,1.f,1.f,0.f,1.f,1.f,1.f,0.f,0.f,0.f,0.f})number(b,n);
    for(unsigned i=0;i<5;++i)integer(b,Model::absent);
    return b;
}
static void rejects(const Bytes& b) {bool rejected=false;try{Model::decode(b.data(),b.size());}catch(const std::runtime_error&){rejected=true;}assert(rejected);}
int main(int argc,char** argv) {
    auto valid=triangle();auto asset=Model::decode(valid.data(),valid.size());assert(asset.vertices.size()==3 && asset.indices.size()==3 && asset.primitives.size()==1);
    for(size_t n=0;n<valid.size();++n)rejects(Bytes(valid.begin(),valid.begin()+n));
    auto bad=valid;bad[0]=0;rejects(bad);
    bad=valid;overwrite(bad,8,0xffffffffu);rejects(bad);
    bad=valid;overwrite(bad,28,0x7fc00000);rejects(bad);
    bad=valid;overwrite(bad,28+3*64,3);rejects(bad);
    bad=valid;overwrite(bad,28+3*64+12,1);rejects(bad);
    bad=valid;overwrite(bad,28+3*64+12+8,1);rejects(bad);
    bad=valid;overwrite(bad,28+3*64+12+16+48,0);rejects(bad);
    bad=valid;bad.push_back(0);rejects(bad);
    bad=valid;overwrite(bad,24,1);rejects(bad);
    if(argc==2) {auto sample=Model::load(argv[1]);assert(sample.vertices.size()>50000 && sample.indices.size()/3>90000 && sample.primitives.size()==6 && sample.textures.size()==15);}
    std::puts("PASS model pack: truncation at every byte, counts, NaN, indices, primitive ranges, material/texture references, trailing data and real sample");
}
