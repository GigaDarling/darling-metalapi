// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace Model {
struct alignas(16) Float4 { float x,y,z,w; };
struct Vertex { Float4 position,normal,uv,tangent; };
static_assert(sizeof(Vertex)==64,"MSL model vertex layout");
struct Primitive { uint32_t first,count,material,reserved; };
struct Material { Float4 base,properties,emissive;std::array<uint32_t,5> textures; };
struct Texture { uint32_t width,height;std::vector<unsigned char> rgba; };
struct Asset {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
    std::vector<Primitive> primitives;
    std::vector<Material> materials;
    std::vector<Texture> textures;
};
constexpr uint32_t absent=0xffffffffu;

class Reader {
    const unsigned char* data;
    size_t size,offset=0;
public:
    Reader(const unsigned char* bytes,size_t length):data(bytes),size(length) {}
    void bytes(void* destination,size_t count) {
        if (count>size-offset) throw std::runtime_error("truncated model pack");
        if (count) std::memcpy(destination,data+offset,count);
        offset+=count;
    }
    uint32_t integer() {
        unsigned char b[4];bytes(b,4);
        return uint32_t(b[0])|uint32_t(b[1])<<8|uint32_t(b[2])<<16|uint32_t(b[3])<<24;
    }
    float number() {
        uint32_t bits=integer();float value;std::memcpy(&value,&bits,4);
        if (!std::isfinite(value)) throw std::runtime_error("non-finite model value");
        return value;
    }
    Float4 vector() {float x=number(),y=number(),z=number(),w=number();return {x,y,z,w};}
    size_t remaining() const {return size-offset;}
};

inline Asset decode(const unsigned char* data,size_t size) {
    if (!data || size>512u*1024u*1024u) throw std::runtime_error("invalid model pack size");
    Reader reader(data,size);char magic[8];reader.bytes(magic,8);
    if (std::memcmp(magic,"DMODEL1\0",8)) throw std::runtime_error("unknown model pack format");
    auto nv=reader.integer(),ni=reader.integer(),np=reader.integer(),nm=reader.integer(),nt=reader.integer();
    if (!nv || nv>2'000'000 || !ni || ni>12'000'000 || ni%3 || !np || np>4096 || !nm || nm>1024 || nt>128)
        throw std::runtime_error("invalid model counts");
    uint64_t minimum=uint64_t(nv)*64+uint64_t(ni)*4+uint64_t(np)*16+uint64_t(nm)*68+uint64_t(nt)*8;
    if (minimum>reader.remaining()) throw std::runtime_error("model counts exceed file size");
    Asset asset;asset.vertices.reserve(nv);asset.indices.reserve(ni);
    for (uint32_t i=0;i<nv;++i) {
        auto p=reader.vector(),n=reader.vector(),uv=reader.vector(),t=reader.vector();
        if (std::abs(p.x)>4 || std::abs(p.y)>4 || std::abs(p.z)>4 || p.w!=1)
            throw std::runtime_error("invalid normalized vertex position");
        asset.vertices.push_back({p,n,uv,t});
    }
    for (uint32_t i=0;i<ni;++i) {
        uint32_t index=reader.integer();if (index>=nv) throw std::runtime_error("vertex index out of range");
        asset.indices.push_back(index);
    }
    uint32_t next=0;
    for (uint32_t i=0;i<np;++i) {
        uint32_t first=reader.integer(),count=reader.integer(),material=reader.integer(),reserved=reader.integer();
        if (first!=next || !count || count%3 || first>ni || count>ni-first || material>=nm || reserved)
            throw std::runtime_error("invalid primitive range or material");
        asset.primitives.push_back({first,count,material,reserved});next=first+count;
    }
    if (next!=ni) throw std::runtime_error("unreferenced model indices");
    for (uint32_t i=0;i<nm;++i) {
        Material material;material.base=reader.vector();material.properties=reader.vector();material.emissive=reader.vector();
        for (auto& slot:material.textures) {slot=reader.integer();if (slot!=absent && slot>=nt) throw std::runtime_error("texture index out of range");}
        if (material.properties.x<0 || material.properties.x>1 || material.properties.y<0 || material.properties.y>1)
            throw std::runtime_error("invalid metallic or roughness factor");
        asset.materials.push_back(material);
    }
    for (uint32_t i=0;i<nt;++i) {
        Texture texture;texture.width=reader.integer();texture.height=reader.integer();
        if (!texture.width || !texture.height || texture.width>2048 || texture.height>2048)
            throw std::runtime_error("invalid texture dimensions");
        size_t bytes=size_t(texture.width)*texture.height*4;
        if (bytes>reader.remaining()) throw std::runtime_error("truncated texture");
        texture.rgba.resize(bytes);reader.bytes(texture.rgba.data(),bytes);asset.textures.push_back(std::move(texture));
    }
    if (reader.remaining()) throw std::runtime_error("trailing model pack data");
    return asset;
}

inline Asset load(const char* path) {
    FILE* file=std::fopen(path,"rb");if (!file) throw std::runtime_error("cannot open model pack");
    if (std::fseek(file,0,SEEK_END)!=0) {std::fclose(file);throw std::runtime_error("cannot seek model pack");}
    long size=std::ftell(file);
    if (size<0 || size>512*1024*1024) {std::fclose(file);throw std::runtime_error("model pack too large");}
    std::rewind(file);std::vector<unsigned char> bytes(size);
    size_t count=std::fread(bytes.data(),1,bytes.size(),file);std::fclose(file);
    if (count!=bytes.size()) throw std::runtime_error("cannot read complete model pack");
    return decode(bytes.data(),bytes.size());
}
}
