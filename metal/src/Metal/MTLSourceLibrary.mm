// SPDX-License-Identifier: MPL-2.0
// Public contract: https://developer.apple.com/documentation/metal/mtldevice/makelibrary(source:options:)
#import <Metal/MTLSourceLibrary.h>
#import <Metal/MTLLibraryInternal.h>
#import <Metal/MTLIndiumErrors.h>

#if DARLING_METAL_ENABLED
#if DARLING_METAL_SOURCE_COMPILER
#include <mslc/mslc.h>
#include <cstring>
#include <memory>
#include <cmath>
#include <cstdint>
#include <map>
#include <set>

static bool sourceReflectionIndex(id value, size_t& index) {
    if (![value isKindOfClass: [NSNumber class]])
        return false;
    double number = [value doubleValue];
    if (!std::isfinite(number) || number < 0 || number > UINT32_MAX || std::floor(number) != number)
        return false;
    index = [value unsignedLongLongValue];
    return true;
}

static bool readSourceBuffers(NSDictionary* entry, Indium::FunctionReflection& function,
                              NSString** reason) {
    if ([entry[@"embedded_samplers"] count]) {
        *reason = @"Source compilation with embedded samplers is not supported yet";
        return false;
    }
    // Indium's address block follows member order, independently of the Metal
    // buffer indices. Preserve the compiler's explicit member mapping.
    std::map<size_t, Indium::BindingDescriptor> members;
    std::set<size_t> indices;
    for (id resource in entry[@"bindings"]) {
        if (![resource isKindOfClass: [NSDictionary class]] ||
            ![resource[@"kind"] isEqual: @"Buffer"] ||
            ![resource[@"descriptor"] isKindOfClass: [NSDictionary class]]) {
            *reason = @"This source compiler bridge currently supports buffer resources only";
            return false;
        }
        size_t index, member, set, binding;
        if (!sourceReflectionIndex(resource[@"metal_index"], index) ||
            !sourceReflectionIndex(resource[@"member"], member) ||
            !sourceReflectionIndex(resource[@"descriptor"][@"set"], set) ||
            !sourceReflectionIndex(resource[@"descriptor"][@"binding"], binding) ||
            binding != 0 || set != (function.functionType == Indium::FunctionType::Fragment ? 1 : 0)) {
            *reason = @"The source compiler returned an invalid buffer address mapping";
            return false;
        }
        Indium::BindingDescriptor descriptor;
        descriptor.type = Indium::BindingType::Buffer;
        descriptor.index = index;
        if (!indices.insert(index).second || !members.emplace(member, descriptor).second) {
            *reason = @"The source compiler returned duplicate buffer mappings";
            return false;
        }
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
    if (![document isKindOfClass: [NSDictionary class]] ||
        ![document[@"reflection_version"] isKindOfClass: [NSNumber class]] ||
        [document[@"reflection_version"] unsignedIntegerValue] != 2 ||
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
        if (!readSourceBuffers(entry, reflection.functions[name], reason))
            return false;
        [names addObject: entry[@"name"]];
    }
    if (reflection.functions.empty()) {
        *reason = @"Source libraries without shader entry points are not supported yet";
        return false;
    }
    return true;
}
#endif

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
    Indium::LibraryReflection reflection;
    NSMutableArray* names = [NSMutableArray array];
    NSString* reason = nil;
    if (!readSourceReflection(document, reflection, names, &reason)) {
        MTLSetError(error, MTLLibraryErrorUnsupported, reason);
        return nil;
    }
    std::string failure;
    auto library = device->newLibrary(bytes, length, reflection, &failure);
    if (!library) {
        MTLSetError(error, MTLLibraryErrorCompileFailure, [NSString stringWithUTF8String: failure.c_str()]);
        return nil;
    }
    return [[MTLLibraryInternal alloc] initWithLibrary: library device: owner functionNames: names];
#else
    MTLSetError(error, MTLLibraryErrorUnsupported, @"Metal source compilation was not enabled at build time");
    return nil;
#endif
}
#endif
