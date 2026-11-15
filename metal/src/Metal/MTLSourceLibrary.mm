// SPDX-License-Identifier: MPL-2.0
// Public contract: https://developer.apple.com/documentation/metal/mtldevice/makelibrary(source:options:)
#import <Metal/MTLSourceLibrary.h>
#import <Metal/MTLLibraryInternal.h>
#import <Metal/MTLIndiumErrors.h>

#if DARLING_METAL_ENABLED
#if DARLING_METAL_SOURCE_COMPILER
#include <mslc/mslc.h>
#endif
#include <cstring>
#include <memory>
#include <cmath>
#include <cstdint>
#include <map>
#include <set>
#include <initializer_list>
#include <limits>
#include <vector>

static bool sourceReflectionIndex(id value, size_t& index) {
    if (![value isKindOfClass: [NSNumber class]])
        return false;
    double number = [value doubleValue];
    if (!std::isfinite(number) || number < 0 || number > UINT32_MAX || std::floor(number) != number)
        return false;
    index = [value unsignedLongLongValue];
    return true;
}

static bool sourceSamplerEnum(id value, std::initializer_list<const char*> names, size_t& result) {
    if (![value isKindOfClass:[NSString class]]) return false;
    size_t index=0;
    for (const char* name:names) {
        if ([value isEqualToString:[NSString stringWithUTF8String:name]]) { result=index; return true; }
        ++index;
    }
    return false;
}

static bool readSourceSampler(id entry, Indium::EmbeddedSamplerDescriptor& sampler) {
    if (![entry isKindOfClass:[NSDictionary class]]) return false;
    size_t s,t,r,mag,min,mip,compare,border,anisotropy,normalized;
    auto address = {"ClampToZero","ClampToEdge","Repeat","MirrorRepeat","ClampToBorderColor"};
    if (!sourceSamplerEnum(entry[@"s_address"],address,s) || !sourceSamplerEnum(entry[@"t_address"],address,t) ||
        !sourceSamplerEnum(entry[@"r_address"],address,r) ||
        !sourceSamplerEnum(entry[@"mag_filter"],{"Nearest","Linear"},mag) ||
        !sourceSamplerEnum(entry[@"min_filter"],{"Nearest","Linear"},min) ||
        !sourceSamplerEnum(entry[@"mip_filter"],{"None","Nearest","Linear"},mip) ||
        !sourceSamplerEnum(entry[@"compare_function"],{"None","Less","LessEqual","Greater","GreaterEqual","Equal","NotEqual","Always","Never"},compare) ||
        !sourceSamplerEnum(entry[@"border_color"],{"TransparentBlack","OpaqueBlack","OpaqueWhite"},border) ||
        !sourceReflectionIndex(entry[@"anisotropy"],anisotropy) || anisotropy<1 || anisotropy>UINT8_MAX ||
        !sourceReflectionIndex(entry[@"normalized_coordinates"],normalized) || normalized>1 ||
        ![entry[@"lod_min"] isKindOfClass:[NSNumber class]] || ![entry[@"lod_max"] isKindOfClass:[NSNumber class]]) return false;
    double low=[entry[@"lod_min"] doubleValue],high=[entry[@"lod_max"] doubleValue];
    if (!std::isfinite(low) || !std::isfinite(high) || low<0 || high<low || high>std::numeric_limits<float>::max()) return false;
    sampler.widthAddressMode=static_cast<Indium::EmbeddedSamplerDescriptor::AddressMode>(s);
    sampler.heightAddressMode=static_cast<Indium::EmbeddedSamplerDescriptor::AddressMode>(t);
    sampler.depthAddressMode=static_cast<Indium::EmbeddedSamplerDescriptor::AddressMode>(r);
    sampler.magnificationFilter=static_cast<Indium::EmbeddedSamplerDescriptor::Filter>(mag);
    sampler.minificationFilter=static_cast<Indium::EmbeddedSamplerDescriptor::Filter>(min);
    sampler.mipmapFilter=static_cast<Indium::EmbeddedSamplerDescriptor::MipFilter>(mip);
    sampler.compareFunction=static_cast<Indium::EmbeddedSamplerDescriptor::CompareFunction>(compare);
    sampler.borderColor=static_cast<Indium::EmbeddedSamplerDescriptor::BorderColor>(border);
    sampler.anisotropyLevel=anisotropy;sampler.usesNormalizedCoordinates=normalized;sampler.lodMin=low;sampler.lodMax=high;
    return true;
}

static bool readSourceResources(NSDictionary* entry, Indium::FunctionReflection& function,
                              NSString** reason) {
    for (id description in entry[@"embedded_samplers"]) {
        Indium::EmbeddedSamplerDescriptor sampler;
        if (!readSourceSampler(description,sampler)) {
            *reason=@"The source compiler returned an unsupported or invalid embedded sampler";
            return false;
        }
        function.embeddedSamplers.push_back(sampler);
    }
    // Indium's address block follows member order, independently of the Metal
    // buffer indices. Preserve the compiler's explicit member mapping.
    std::map<size_t, Indium::BindingDescriptor> members;
    std::set<std::pair<unsigned, size_t>> indices;
    std::set<size_t> descriptors;
    bool hasBuffers = false;
    for (id resource in entry[@"bindings"]) {
        if (![resource isKindOfClass: [NSDictionary class]] ||
            ![resource[@"kind"] isKindOfClass: [NSString class]] ||
            ![resource[@"descriptor"] isKindOfClass: [NSDictionary class]]) {
            *reason = @"The source compiler returned an invalid resource description";
            return false;
        }
        NSString* kind = resource[@"kind"];
        bool embedded=[kind isEqual:@"Sampler"] && resource[@"embedded_sampler"]!=nil;
        size_t index=SIZE_MAX,set,binding,embeddedIndex=SIZE_MAX;
        if ((!embedded && !sourceReflectionIndex(resource[@"metal_index"], index)) ||
            (embedded && (!sourceReflectionIndex(resource[@"embedded_sampler"],embeddedIndex) || embeddedIndex>=function.embeddedSamplers.size())) ||
            !sourceReflectionIndex(resource[@"descriptor"][@"set"], set) ||
            !sourceReflectionIndex(resource[@"descriptor"][@"binding"], binding) ||
            set != (function.functionType == Indium::FunctionType::Fragment ? 1 : 0)) {
            *reason = @"The source compiler returned an invalid resource mapping";
            return false;
        }
        Indium::BindingDescriptor descriptor;
        descriptor.index = index;
        descriptor.internalIndex = binding;
        descriptor.embeddedSamplerIndex=embeddedIndex;
        if ([kind isEqual: @"Buffer"]) {
            size_t member;
            descriptor.type = Indium::BindingType::Buffer;
            if (binding != 0 || !sourceReflectionIndex(resource[@"member"], member) ||
                !members.emplace(member, descriptor).second) {
                *reason = @"The source compiler returned an invalid buffer address mapping";
                return false;
            }
            hasBuffers = true;
        } else if ([kind isEqual: @"Texture"] || [kind isEqual: @"Sampler"]) {
            descriptor.type = [kind isEqual: @"Texture"] ? Indium::BindingType::Texture : Indium::BindingType::Sampler;
            if (descriptor.type == Indium::BindingType::Texture) {
                size_t access;
                if (!sourceSamplerEnum(resource[@"texture_access"],{"Sample","Read","Write","ReadWrite"},access)) {
                    *reason=@"The source compiler returned an unknown texture access type";
                    return false;
                }
                descriptor.textureAccessType=static_cast<Indium::TextureAccessType>(access);
            }
            if (!descriptors.insert(binding).second) {
                *reason = @"The source compiler returned duplicate descriptor bindings";
                return false;
            }
            function.bindings.push_back(descriptor);
        } else {
            *reason = @"The source compiler returned an unsupported resource kind";
            return false;
        }
        if (!embedded && !indices.emplace(static_cast<unsigned>(descriptor.type), index).second) {
            *reason = @"The source compiler returned duplicate resource indices";
            return false;
        }
    }
    if (hasBuffers && descriptors.count(0)) {
        *reason = @"A source resource overlaps the buffer address block";
        return false;
    }
    for (size_t member = 0; member < members.size(); ++member) {
        auto found = members.find(member);
        if (found == members.end()) {
            *reason = @"The source compiler returned an incomplete buffer address block";
            return false;
        }
        function.bindings.push_back(found->second);
    }
    return true;
}

static bool readSourceReflection(NSDictionary* document, Indium::LibraryReflection& reflection,
                                NSMutableArray* names, NSString** reason) {
    size_t version=0;
    if (![document isKindOfClass: [NSDictionary class]] ||
        !sourceReflectionIndex(document[@"reflection_version"],version) || version != 2 ||
        ![document[@"entry_points"] isKindOfClass: [NSArray class]]) {
        *reason = @"The source compiler returned an unsupported reflection document";
        return false;
    }
    for (id entry in document[@"entry_points"]) {
        if (![entry isKindOfClass: [NSDictionary class]] ||
            ![entry[@"name"] isKindOfClass: [NSString class]] || ![entry[@"name"] length] ||
            ![entry[@"stage"] isKindOfClass: [NSString class]] ||
            ![entry[@"bindings"] isKindOfClass: [NSArray class]] ||
            ![entry[@"embedded_samplers"] isKindOfClass: [NSArray class]]) {
            *reason = @"The source compiler returned an invalid function description";
            return false;
        }
        Indium::FunctionType type;
        NSString* stage = entry[@"stage"];
        if ([stage isEqualToString: @"vertex"])
            type = Indium::FunctionType::Vertex;
        else if ([stage isEqualToString: @"fragment"])
            type = Indium::FunctionType::Fragment;
        else if ([stage isEqualToString: @"compute"])
            type = Indium::FunctionType::Kernel;
        else {
            *reason = @"The source compiler returned an unsupported shader stage";
            return false;
        }
        std::string name([entry[@"name"] UTF8String]);
        if (!reflection.functions.emplace(name, Indium::FunctionReflection {}).second) {
            *reason = @"The source compiler returned a duplicate function name";
            return false;
        }
        reflection.functions[name].functionType = type;
        if (!readSourceResources(entry, reflection.functions[name], reason))
            return false;
        [names addObject: entry[@"name"]];
    }
    if (reflection.functions.empty()) {
        *reason = @"Source libraries without shader entry points are not supported yet";
        return false;
    }
    return true;
}

static id<MTLLibrary> newReflectedLibrary(std::shared_ptr<Indium::Device> device,
    id<MTLDevice> owner, const void* bytes, size_t length, id document,
    MTLLibraryError reflectionError, NSError** error) {
    Indium::LibraryReflection reflection;
    NSMutableArray* names = [NSMutableArray array];
    NSString* reason = nil;
    if (!readSourceReflection(document, reflection, names, &reason)) {
        MTLSetError(error, reflectionError, reason);
        return nil;
    }
    std::string failure;
    auto library = device->newLibrary(bytes, length, reflection, &failure);
    if (!library) {
        MTLSetError(error, MTLLibraryErrorCompileFailure, [NSString stringWithUTF8String: failure.c_str()]);
        return nil;
    }
    return [[MTLLibraryInternal alloc] initWithLibrary: library device: owner functionNames: names];
}

// The open Darling toolchain's container, distinct from Apple's AIR encoding.
// Header layout: demo/PORTABLE-LIBRARY.md. No original binary was inspected.
static const uint8_t portableMagic[] = {'D','M','S','L','S','P','V',0};

// Validate the metadata this container supplies to Indium's producer-side
// interface. Instruction framing/OpEntryPoint follow the public SPIR-V spec:
// https://registry.khronos.org/SPIR-V/specs/unified1/SPIRV.html#OpEntryPoint
static bool portableEntriesMatch(const std::vector<uint32_t>& code, NSDictionary* document) {
    if (code[0]!=0x07230203 || code[4]!=0 || ![document isKindOfClass:[NSDictionary class]] ||
        ![document[@"entry_points"] isKindOfClass:[NSArray class]]) return false;
    std::map<std::string,std::string> entries;
    for (size_t offset=5;offset<code.size();) {
        const uint32_t words=code[offset]>>16,opcode=code[offset]&0xffff;
        if (!words || words>code.size()-offset) return false;
        if (opcode==15) {
            if (words<4) return false;
            // A byte view is permitted for inspecting words; the checked
            // instruction length bounds memchr before constructing a string.
            const char* name=reinterpret_cast<const char*>(code.data()+offset+3);
            const void* end=std::memchr(name,0,(words-3)*sizeof(uint32_t));
            if (!end || end==name) return false;
            const char* stage=code[offset+1]==0?"vertex":code[offset+1]==4?"fragment":code[offset+1]==5?"compute":nullptr;
            if (!stage || !entries.emplace(std::string(name,static_cast<const char*>(end)-name),stage).second) return false;
        }
        offset+=words;
    }
    if (entries.size()!=[document[@"entry_points"] count]) return false;
    for (id entry in document[@"entry_points"]) {
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"name"] isKindOfClass:[NSString class]] ||
            ![entry[@"stage"] isKindOfClass:[NSString class]]) return false;
        const char* name=[entry[@"name"] UTF8String];
        if (!name || std::strlen(name)!=[entry[@"name"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) return false;
        auto found=entries.find(name);
        if (found==entries.end() || ![entry[@"stage"] isEqualToString:[NSString stringWithUTF8String:found->second.c_str()]]) return false;
        entries.erase(found);
    }
    return entries.empty();
}

bool MTLIsPortableLibrary(const void* bytes, size_t length) {
    return bytes && length >= sizeof(portableMagic) &&
        std::memcmp(bytes, portableMagic, sizeof(portableMagic)) == 0;
}

id<MTLLibrary> MTLLoadPortableLibrary(std::shared_ptr<Indium::Device> device,
    id<MTLDevice> owner, const void* bytes, size_t length, NSError** error) {
    if (!MTLIsPortableLibrary(bytes,length) || length < 24) {
        MTLSetError(error, MTLLibraryErrorCompileFailure, @"Truncated Darling shader library header");
        return nil;
    }
    const auto* data=static_cast<const uint8_t*>(bytes);
    auto word=[&](size_t offset) -> uint32_t {
        return uint32_t(data[offset]) | uint32_t(data[offset+1])<<8 |
            uint32_t(data[offset+2])<<16 | uint32_t(data[offset+3])<<24;
    };
    if (word(8)!=1) {
        MTLSetError(error, MTLLibraryErrorUnsupported, @"Unsupported Darling shader library version");
        return nil;
    }
    const size_t codeLength=word(12),jsonLength=word(16);
    if (word(20)!=0 || codeLength<20 || codeLength%4 || codeLength>length-24 ||
        jsonLength==0 || jsonLength!=length-24-codeLength) {
        MTLSetError(error, MTLLibraryErrorCompileFailure, @"Invalid Darling shader library lengths or reserved field");
        return nil;
    }
    NSData* json=[NSData dataWithBytes:data+24+codeLength length:jsonLength];
    id document=[NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    // A dispatch_data region may be unaligned; copy before Indium/Vulkan reads
    // uint32 words rather than casting the caller's potentially unaligned bytes.
    std::vector<uint32_t> code(codeLength/4);
    std::memcpy(code.data(),data+24,codeLength);
    if (!portableEntriesMatch(code,document)) {
        MTLSetError(error, MTLLibraryErrorCompileFailure, @"Darling shader library entry points do not match its SPIR-V module");
        return nil;
    }
    return newReflectedLibrary(device,owner,code.data(),codeLength,document,MTLLibraryErrorCompileFailure,error);
}

id<MTLLibrary> MTLCompileSourceLibrary(std::shared_ptr<Indium::Device> device,
    id<MTLDevice> owner, NSString* source, NSError** error) {
#if DARLING_METAL_SOURCE_COMPILER
    MslcOptions options;
    mslc_default_options(&options);
    uint8_t* bytes = nullptr;
    size_t length = 0;
    char* reflectionText = nullptr;
    char* diagnostic = nullptr;
    int status = mslc_translate(source.UTF8String, [source lengthOfBytesUsingEncoding: NSUTF8StringEncoding],
        &options, &bytes, &length, &reflectionText, &diagnostic);
    // mslc transfers ownership of all output buffers, including diagnostics on failure.
    std::unique_ptr<uint8_t, decltype(&mslc_free)> ownedBytes(bytes, mslc_free);
    std::unique_ptr<char, decltype(&mslc_free)> ownedReflection(reflectionText, mslc_free);
    std::unique_ptr<char, decltype(&mslc_free)> ownedDiagnostic(diagnostic, mslc_free);
    if (status || !bytes || !reflectionText) {
        MTLSetError(error, MTLLibraryErrorCompileFailure, diagnostic
            ? [NSString stringWithUTF8String: diagnostic] : @"The source compiler failed");
        return nil;
    }
    NSData* data = [NSData dataWithBytes: reflectionText length: std::strlen(reflectionText)];
    id document = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
    return newReflectedLibrary(device,owner,bytes,length,document,MTLLibraryErrorUnsupported,error);
#else
    MTLSetError(error, MTLLibraryErrorUnsupported, @"Metal source compilation was not enabled at build time");
    return nil;
#endif
}
#endif
