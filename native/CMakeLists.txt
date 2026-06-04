cmake_minimum_required(VERSION 3.20)
project(macglcompat LANGUAGES C CXX OBJC)

if(NOT DEFINED CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architectures" FORCE)
endif()

set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJC_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(JNI REQUIRED)

# ---------------------------------------------------------------------------
# A1: shader-translation toolchain (GLSL -> SPIR-V -> MSL).
# Pure CPU libraries — fully CI-testable without a GPU. All three Khronos repos
# pinned to the same Vulkan SDK tag so they are known-compatible.
# ---------------------------------------------------------------------------
include(FetchContent)
set(MGL_KHRONOS_TAG "vulkan-sdk-1.3.296.0")

# SPIRV-Headers — needed by glslang's SPIR-V backend.
FetchContent_Declare(spirv_headers
    GIT_REPOSITORY https://github.com/KhronosGroup/SPIRV-Headers.git
    GIT_TAG ${MGL_KHRONOS_TAG}
    GIT_SHALLOW TRUE)

# glslang — GLSL -> SPIR-V. Trim everything we don't use.
set(ENABLE_OPT OFF CACHE BOOL "" FORCE)            # no SPIRV-Tools optimizer
set(ENABLE_SPVREMAPPER OFF CACHE BOOL "" FORCE)
set(ENABLE_GLSLANG_BINARIES OFF CACHE BOOL "" FORCE)
set(GLSLANG_TESTS OFF CACHE BOOL "" FORCE)
set(GLSLANG_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
FetchContent_Declare(glslang
    GIT_REPOSITORY https://github.com/KhronosGroup/glslang.git
    GIT_TAG ${MGL_KHRONOS_TAG}
    GIT_SHALLOW TRUE)

# SPIRV-Cross — SPIR-V -> MSL. MSL backend depends on the GLSL backend + core.
set(SPIRV_CROSS_CLI OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_GLSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_MSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_HLSL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_CPP OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_REFLECT OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_UTIL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_STATIC ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_SHARED OFF CACHE BOOL "" FORCE)
FetchContent_Declare(spirv_cross
    GIT_REPOSITORY https://github.com/KhronosGroup/SPIRV-Cross.git
    GIT_TAG ${MGL_KHRONOS_TAG}
    GIT_SHALLOW TRUE)

FetchContent_MakeAvailable(spirv_headers glslang spirv_cross)

# ---------------------------------------------------------------------------
# The mod's native backend (loaded by the JVM). Does NOT link the transpiler yet
# — that wiring lands in A2 when we actually translate shaders.
# ---------------------------------------------------------------------------
add_library(macglcompat SHARED
    src/core.m
    src/bridge.m
    src/compute.m
    src/iosurface.m
    src/trampolines.c
)
target_include_directories(macglcompat PRIVATE
    ${JNI_INCLUDE_DIRS}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_link_libraries(macglcompat PRIVATE
    "-framework Foundation"
    "-framework Metal"
    "-framework IOSurface"
    "-framework CoreVideo"
)
set_target_properties(macglcompat PROPERTIES
    PREFIX "lib" OUTPUT_NAME "macglcompat" SUFFIX ".dylib")

# ---------------------------------------------------------------------------
# Headless self-tests (no Minecraft, no human).
# ---------------------------------------------------------------------------

# Metal compute — needs a device (skips on CI runners that lack one).
add_executable(headless_compute_test test/headless_compute_test.m)
target_link_libraries(headless_compute_test PRIVATE
    "-framework Foundation" "-framework Metal")

# IOSurface bridge — needs a device (skips without one).
add_executable(headless_iosurface_test
    test/headless_iosurface_test.m src/core.m src/iosurface.m)
target_include_directories(headless_iosurface_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(headless_iosurface_test PRIVATE
    "-framework Foundation" "-framework Metal" "-framework IOSurface")

# Trampoline resolution + glGetString version spoof (B) — pure C, runs on CI.
add_executable(trampoline_test test/trampoline_test.c src/trampolines.c)
target_include_directories(trampoline_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include)

# Transpiler (A2) + its unit tests (A3) — pure CPU, ACTUALLY RUN on CI. Translates
# GLSL compute -> SPIR-V -> MSL and asserts the output. No GPU needed.
add_executable(transpiler_test
    test/transpiler_test.cpp
    src/transpiler.cpp)
target_include_directories(transpiler_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(transpiler_test PRIVATE
    glslang SPIRV glslang-default-resource-limits
    spirv-cross-msl spirv-cross-glsl spirv-cross-core)
