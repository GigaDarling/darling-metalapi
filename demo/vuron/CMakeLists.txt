set(VURON_SOURCE_DIR "${CMAKE_SOURCE_DIR}/build/metal-baseline/vendor/Vuron" CACHE PATH "Pinned MIT Vuron source checkout")
if(NOT EXISTS "${VURON_SOURCE_DIR}/src/renderer/MetalRenderer.mm")
    return()
endif()
set(VURON_BUNDLE "${CMAKE_CURRENT_BINARY_DIR}/vuron.app")
file(MAKE_DIRECTORY "${VURON_BUNDLE}/Contents/MacOS/src/renderer")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${VURON_SOURCE_DIR}/src/renderer/MetalRenderer.mm"
    "${VURON_SOURCE_DIR}/src/platform/mac/MacWindow.mm" "${CMAKE_CURRENT_SOURCE_DIR}/prepare.py")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/prepare.py"
    --source "${VURON_SOURCE_DIR}" --output "${CMAKE_CURRENT_BINARY_DIR}"
    COMMAND_ERROR_IS_FATAL ANY)
configure_file(Info.plist "${VURON_BUNDLE}/Contents/Info.plist" COPYONLY)
configure_file("${VURON_SOURCE_DIR}/LICENSE" "${VURON_BUNDLE}/Contents/LICENSE" COPYONLY)
configure_file("${VURON_SOURCE_DIR}/src/renderer/Shaders.metal" "${VURON_BUNDLE}/Contents/MacOS/src/renderer/Shaders.metal" COPYONLY)
file(COPY "${VURON_SOURCE_DIR}/src/assets" "${VURON_SOURCE_DIR}/src/levels" DESTINATION "${VURON_BUNDLE}/Contents/MacOS/src")
add_darling_executable(vuron-game
    "${VURON_SOURCE_DIR}/src/main.cpp"
    "${VURON_SOURCE_DIR}/src/core/Memory.cpp"
    "${CMAKE_CURRENT_BINARY_DIR}/MacWindow.mm"
    "${CMAKE_CURRENT_BINARY_DIR}/MetalRenderer.mm")
target_include_directories(vuron-game PRIVATE "${VURON_SOURCE_DIR}/src/renderer" "${VURON_SOURCE_DIR}/src")
target_compile_options(vuron-game PRIVATE -fblocks)
set_target_properties(vuron-game PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON
    RUNTIME_OUTPUT_DIRECTORY "${VURON_BUNDLE}/Contents/MacOS")
target_link_libraries(vuron-game AppKit CoreVideo Metal QuartzCore Foundation CoreGraphics cxx)
add_darling_executable(metal-derivatives-test derivatives-test.mm)
target_compile_options(metal-derivatives-test PRIVATE -fobjc-arc -fblocks)
set_target_properties(metal-derivatives-test PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
target_link_libraries(metal-derivatives-test Metal Foundation cxx)
add_darling_executable(metal-game-headers-test headers-test.mm)
set_target_properties(metal-game-headers-test PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
target_link_libraries(metal-game-headers-test CoreGraphics AppKit QuartzCore Metal Foundation cxx)
