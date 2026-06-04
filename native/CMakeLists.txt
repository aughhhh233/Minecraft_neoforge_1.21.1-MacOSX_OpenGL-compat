cmake_minimum_required(VERSION 3.20)
project(macglcompat LANGUAGES C OBJC)

# Apple Silicon only. (Phase 0 also builds fine as a universal slice if needed.)
if(NOT DEFINED CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architectures" FORCE)
endif()

set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJC_STANDARD_REQUIRED ON)

# JNI headers (jni.h + jni_md.h). Provided by the JDK that setup-java installs.
find_package(JNI REQUIRED)

add_library(macglcompat SHARED
    src/bridge.m
    src/compute.m
    src/iosurface.m
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
    PREFIX "lib"
    OUTPUT_NAME "macglcompat"
    SUFFIX ".dylib"
)

# --- Headless verification executable -------------------------------------
# Proves the runner has a usable Metal device and that a real compute dispatch
# + buffer readback produces correct results. This is the Phase 0 "green light"
# for the Metal path — it needs no Minecraft and no human.
add_executable(headless_compute_test test/headless_compute_test.m)
target_link_libraries(headless_compute_test PRIVATE
    "-framework Foundation"
    "-framework Metal"
)
