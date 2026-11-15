// SPDX-License-Identifier: GPL-3.0-or-later
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static void requireLibrary(bool value,const char* name) {
    if (!value) { std::fprintf(stderr,"FAIL portable library: %s\n",name);std::exit(1); }
}
static uint32_t word(NSData* data,size_t offset) {
    const auto* bytes=static_cast<const unsigned char*>(data.bytes)+offset;
    return uint32_t(bytes[0])|uint32_t(bytes[1])<<8|uint32_t(bytes[2])<<16|uint32_t(bytes[3])<<24;
}
static void setWord(NSMutableData* data,size_t offset,uint32_t value) {
    auto* bytes=static_cast<unsigned char*>(data.mutableBytes)+offset;
    for (unsigned i=0;i<4;++i) bytes[i]=(value>>(8*i))&255;
}
static dispatch_data_t dispatchBytes(NSData* data) {
    void* copy=std::malloc(data.length);requireLibrary(copy!=nullptr,"dispatch storage allocation");
    std::memcpy(copy,data.bytes,data.length);
    return dispatch_data_create(copy,data.length,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),DISPATCH_DATA_DESTRUCTOR_FREE);
}
static id<MTLLibrary> load(id<MTLDevice> device,NSData* data,NSError** error) {
    dispatch_data_t region=dispatchBytes(data);
    id<MTLLibrary> library=[device newLibraryWithData:region error:error];
#if !OS_OBJECT_USE_OBJC
    dispatch_release(region);
#endif
    return library;
}
static void reject(id<MTLDevice> device,NSData* data,MTLLibraryError code,const char* name) {
    NSError* error=nil;
    requireLibrary(load(device,data,&error)==nil && error.code==code && [error.domain isEqual:MTLLibraryErrorDomain],name);
    requireLibrary(load(device,data,nil)==nil,"nil error output is accepted");
}
void verifyPortableLibraries() {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();requireLibrary(device!=nil,"device");
    NSURL* url=[[NSBundle mainBundle] URLForResource:@"default" withExtension:@"metallib"];
    NSData* source=[NSData dataWithContentsOfURL:url];requireLibrary(source.length>24,"packaged shader fixture");
    NSError* error=nil;
    id<MTLLibrary> library=[device newLibraryWithURL:url error:&error];
    requireLibrary(library && !error,"URL library loads");
    requireLibrary([NSSet setWithArray:library.functionNames].count==2,"functionNames are populated");
    requireLibrary([library newFunctionWithName:@"vertexShader"].functionType==MTLFunctionTypeVertex,"vertex function type");
    requireLibrary([library newFunctionWithName:@"fragmentShader"].functionType==MTLFunctionTypeFragment,"fragment function type");
    requireLibrary([library newFunctionWithName:@"not_a_shader"]==nil,"missing function returns nil");
    requireLibrary(load(device,source,&error)!=nil && !error,"dispatch data library loads");
    dispatch_data_t first=dispatchBytes([source subdataWithRange:NSMakeRange(0,17)]);
    dispatch_data_t second=dispatchBytes([source subdataWithRange:NSMakeRange(17,source.length-17)]);
    dispatch_data_t combined=dispatch_data_create_concat(first,second);
    requireLibrary([device newLibraryWithData:combined error:&error]!=nil && !error,"noncontiguous dispatch regions load");
#if !OS_OBJECT_USE_OBJC
    dispatch_release(combined);dispatch_release(first);dispatch_release(second);
#endif
    requireLibrary([device newDefaultLibrary]!=nil,"default main bundle library loads");
    requireLibrary([device newDefaultLibraryWithBundle:[NSBundle mainBundle] error:&error]!=nil && !error,"explicit bundle library loads");
    unsigned failures=0;
    for (unsigned length=8;length<24;++length) { reject(device,[source subdataWithRange:NSMakeRange(0,length)],MTLLibraryErrorCompileFailure,"truncated header");++failures; }
    for (unsigned field=0;field<6;++field) {
        NSMutableData* bad=[source mutableCopy];
        if (field==0) setWord(bad,8,2);
        if (field==1) setWord(bad,12,UINT32_MAX);
        if (field==2) setWord(bad,12,21);
        if (field==3) setWord(bad,16,0);
        if (field==4) setWord(bad,20,1);
        if (field==5) [bad appendBytes:"X" length:1];
        reject(device,bad,field==0?MTLLibraryErrorUnsupported:MTLLibraryErrorCompileFailure,"invalid header field or trailing bytes");++failures;
    }
    NSMutableData* badCode=[source mutableCopy];setWord(badCode,24,0);
    reject(device,badCode,MTLLibraryErrorCompileFailure,"bad SPIR-V magic");++failures;
    const size_t offset=24+word(source,12);
    for (unsigned mode=0;mode<10;++mode) {
        NSMutableDictionary* doc=[NSJSONSerialization JSONObjectWithData:[source subdataWithRange:NSMakeRange(offset,source.length-offset)] options:NSJSONReadingMutableContainers error:nil];
        if (mode==0) doc[@"reflection_version"]=@2.5;
        if (mode==1) doc[@"entry_points"]=@[];
        if (mode==2) [doc[@"entry_points"] addObject:doc[@"entry_points"][0]];
        if (mode==3) doc[@"entry_points"][0][@"stage"]=@"unsupported";
        if (mode==4) doc[@"entry_points"][0][@"bindings"][0][@"descriptor"]=@[];
        if (mode==5) doc[@"entry_points"][0][@"bindings"][0][@"metal_index"]=@(-1);
        if (mode==6) doc[@"entry_points"][0][@"bindings"][1][@"member"]=@7;
        if (mode==7) doc[@"entry_points"][0][@"bindings"][0][@"descriptor"][@"set"]=@1;
        if (mode==8) doc[@"entry_points"][1][@"stage"]=@"compute";
        if (mode==9) doc[@"entry_points"][1][@"name"]=@"not_in_the_module";
        NSData* json=[NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
        NSMutableData* bad=[NSMutableData dataWithData:[source subdataWithRange:NSMakeRange(0,offset)]];
        [bad appendData:json];setWord(bad,16,uint32_t(json.length));
        reject(device,bad,MTLLibraryErrorCompileFailure,"invalid reflection or resource layout");++failures;
    }
    NSMutableData* invalidJSON=[source mutableCopy];static_cast<unsigned char*>(invalidJSON.mutableBytes)[offset]=0xff;
    reject(device,invalidJSON,MTLLibraryErrorCompileFailure,"invalid reflection encoding");++failures;
    for (unsigned mode=0;mode<2;++mode) {
        NSMutableData* bad=[source mutableCopy];
        setWord(bad,44,mode?0xffff0011:0);
        reject(device,bad,MTLLibraryErrorCompileFailure,"invalid SPIR-V instruction framing");++failures;
    }
    std::printf("PASS portable libraries: URL, default bundle, dispatch data, segmented data, entry points; %u rejection cases with/without NSError\n",failures);
}
