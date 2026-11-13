# SPDX-FileCopyrightText: 2026 Darling Developers
# SPDX-License-Identifier: MPL-2.0

project(metal)

remove_sdk_framework(Metal)
remove_sdk_framework(MetalKit)
remove_sdk_framework(MetalPerformanceShaders)

if (BUILD_METAL)
	add_subdirectory(deps/indium)
endif()

set(MSLC_SOURCE_DIR "" CACHE PATH "Optional MIT-licensed mslc checkout for Metal source compilation")
if (BUILD_METAL AND MSLC_SOURCE_DIR)
	include("${MSLC_SOURCE_DIR}/sources.cmake")
	add_darling_static_library(metal_source_compiler FAT SOURCES ${MSLC_LIBRARY_SOURCES})
	target_include_directories(metal_source_compiler PUBLIC ${MSLC_PUBLIC_INCLUDE_DIRS}
		PRIVATE ${MSLC_PRIVATE_INCLUDE_DIRS})
	target_compile_options(metal_source_compiler PRIVATE -fvisibility=hidden)
	set_target_properties(metal_source_compiler PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
	install(FILES "${MSLC_SOURCE_DIR}/LICENSE" DESTINATION share/licenses/darling-metal RENAME mslc-LICENSE)
endif()

#
# Metal
#

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "1.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(Metal
	VERSION ${FRAMEWORK_VERSION}
	HEADER "include/Metal"
)

if (BUILD_METAL)
	set(METAL_LINK_INDIUM indium)
else()
	set(METAL_LINK_INDIUM "")
endif()

add_framework(Metal
	# Metal is not supported in 32-bit apps, but it does still link successfully into such apps.
	# thus, we have to provide a 32-bit build of the framework, but it doesn't have to provide any
	# functionality. so e.g. we can use modern objc features like non-fragile classes.
	FAT
	CURRENT_VERSION
	VERSION ${FRAMEWORK_VERSION}

	SOURCES
		src/Metal/MTLAccelerationStructure.mm
		src/Metal/MTLAccelerationStructureDescriptor.mm
		src/Metal/MTLAccelerationStructureGeometryDescriptor.mm
		src/Metal/MTLArgument.mm
		src/Metal/MTLArgumentDescriptor.mm
		src/Metal/MTLBinaryArchive.mm
		src/Metal/MTLBlitCommandEncoder.mm
		src/Metal/MTLBuffer.mm
		src/Metal/MTLCaptureManager.mm
		src/Metal/MTLCommandBuffer.mm
		src/Metal/MTLCommandBufferDescriptor.mm
		src/Metal/MTLCommandQueue.mm
		src/Metal/MTLCompileOptions.mm
		src/Metal/MTLComputeCommandEncoder.mm
		src/Metal/MTLComputePipeline.mm
		src/Metal/MTLCounterSampleBuffer.mm
		src/Metal/MTLDepthStencilDescriptor.mm
		src/Metal/MTLDevice.mm
		src/Metal/MTLSourceLibrary.mm
		src/Metal/MTLDrawable.mm
		src/Metal/MTLFunctionConstantValues.mm
		src/Metal/MTLHeap.mm
		src/Metal/MTLIndirectCommandBuffer.mm
		src/Metal/MTLIntersectionFunctionTable.mm
		src/Metal/MTLIOSurfaceCopy.mm
		src/Metal/MTLLibrary.mm
		src/Metal/MTLLinkedFunctions.mm
		src/Metal/MTLPipeline.mm
		src/Metal/MTLRenderCommandEncoder.mm
		src/Metal/MTLRenderPipeline.mm
		src/Metal/MTLSamplerDescriptor.mm
		src/Metal/MTLSamplerState.mm
		src/Metal/MTLSharedEvent.mm
		src/Metal/MTLStencilDescriptor.mm
		src/Metal/MTLTexture.mm
		src/Metal/MTLTextureDescriptor.mm
		src/Metal/MTLTileRenderPipeline.mm
		src/Metal/MTLVertexDescriptor.mm
		src/Metal/Metal.mm

	DEPENDENCIES
		system
		objc
		Foundation
		IOSurface
		${METAL_LINK_INDIUM}
		cxx
)

set_target_properties(Metal
	PROPERTIES
		CXX_STANDARD 17
		CXX_STANDARD_REQUIRED ON
		CXX_EXTENSIONS OFF
)

target_include_directories(Metal PUBLIC
	include
)

target_include_directories(Metal PRIVATE
	private-include
)

if (TARGET metal_source_compiler)
	target_link_libraries(Metal PRIVATE metal_source_compiler)
	target_compile_definitions(Metal PRIVATE DARLING_METAL_SOURCE_COMPILER=1)
endif()

# private API
add_library(Metal_private INTERFACE)
target_link_libraries(Metal_private INTERFACE
	Metal
)
target_include_directories(Metal_private INTERFACE
	private-include
)

if (BUILD_METAL)
	target_compile_definitions(Metal PUBLIC
		DARLING_METAL_ENABLED=1
	)
endif()

#
# MetalKit
#

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "113.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(MetalKit
	VERSION ${FRAMEWORK_VERSION}
	HEADER "include/MetalKit"
)

add_framework(MetalKit
	FAT
	CURRENT_VERSION
	VERSION ${FRAMEWORK_VERSION}

	SOURCES
		src/MetalKit/MTKModel.m
		src/MetalKit/MTKTextureLoader.m
		src/MetalKit/MTKView.m

	DEPENDENCIES
		AppKit
		system
		objc
		Foundation
		Metal
		QuartzCore
		CoreGraphics
		ImageIO
)

target_include_directories(MetalKit PUBLIC
	include
)

target_include_directories(MetalKit PRIVATE
	private-include
	${CMAKE_SOURCE_DIR}/src/external/foundation/internal_include
)

#
# MetalPerformanceShaders
#

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "122.5.6")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(MetalPerformanceShaders
	VERSION ${FRAMEWORK_VERSION}
	HEADER "include/MetalPerformanceShaders"
)

add_framework(MetalPerformanceShaders
	FAT
	CURRENT_VERSION
	VERSION ${FRAMEWORK_VERSION}

	SOURCES
		src/MPSKernel.m

	DEPENDENCIES
		system
		objc
		Foundation
		Metal
)

target_include_directories(MetalPerformanceShaders PUBLIC
	include
)

target_include_directories(MetalPerformanceShaders PRIVATE
	private-include
)
