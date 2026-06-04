cmake_minimum_required(VERSION 3.20)
project(macglcompat LANGUAGES C OBJC)

if(NOT DEFINED CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architectures" FORCE)
endif()

set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJC_STANDARD_REQUIRED ON)

# JNI headers (jni.h + jni_md.h). Provided by the JDK that setup-java installs.
find_package(JNI REQUIRED)

# --- The mod's native backend (loaded by the JVM) -------------------------
add_library(macglcompat SHARED
    src/core.m        # device bring-up + function resolution (no JNI)
    src/bridge.m      # JNI surface only
    src/compute.m     # Phase 2 (empty)
    src/iosurface.m   # Phase 1a: IOSurface <-> MTLTexture bridge
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

# --- Headless verification executables (no Minecraft, no human) ------------

# Proves Metal compute works on this host.
add_executable(headless_compute_test test/headless_compute_test.m)
target_link_libraries(headless_compute_test PRIVATE
    "-framework Foundation"
    "-framework Metal"
)

# Proves the IOSurface<->MTLTexture bridge shares GPU memory. Links the non-JNI
# core + the bridge implementation directly (no jni.h needed).
add_executable(headless_iosurface_test
    test/headless_iosurface_test.m
    src/core.m
    src/iosurface.m
)
target_include_directories(headless_iosurface_test PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_link_libraries(headless_iosurface_test PRIVATE
    "-framework Foundation"
    "-framework Metal"
    "-framework IOSurface"
)
