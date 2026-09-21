cmake_minimum_required(VERSION 3.31.6)

project("ai-chat" VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED true)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED true)

if(NOT DEFINED ANDROID_ABI OR NOT ANDROID_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "Pandora local AI currently supports arm64-v8a only")
endif()

# Keep the proven portable arm64 CPU backend as the mandatory fallback.
# Build Vulkan into the same native runtime so eligible phones can offload a
# bounded number of layers without making local chat depend on GPU success.
set(GGML_SYSTEM_ARCH "ARM")
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN ON CACHE BOOL "" FORCE)

# Android cross-compilation finds target Vulkan from the NDK, while
# SPIRV-Headers is a host-side CMake package used to generate shaders.
# The workflow exports the discovered host package directory explicitly so
# CMake does not incorrectly restrict package lookup to the Android sysroot.
if(DEFINED ENV{PANDORA_SPIRV_HEADERS_DIR})
    set(SPIRV-Headers_DIR "$ENV{PANDORA_SPIRV_HEADERS_DIR}" CACHE PATH "" FORCE)
endif()

set(LLAMA_SRC "${CMAKE_CURRENT_LIST_DIR}/../../../../llama.cpp")
if(NOT EXISTS "${LLAMA_SRC}/CMakeLists.txt")
    message(FATAL_ERROR "Pinned llama.cpp source is missing from android/llama.cpp")
endif()

add_subdirectory("${LLAMA_SRC}" build-llama)

# Android's NDK exposes the Vulkan C API but not the full Vulkan-Hpp header
# set required by the pinned ggml-vulkan backend. CI/build lanes materialize
# only the architecture-neutral Vulkan headers into an isolated directory;
# never add the host /usr/include tree to an Android cross-compile.
if(TARGET ggml-vulkan AND DEFINED ENV{PANDORA_VULKAN_HEADERS_DIR})
    target_include_directories(ggml-vulkan PRIVATE "$ENV{PANDORA_VULKAN_HEADERS_DIR}")
endif()

add_library(ai-chat SHARED
    "${CMAKE_CURRENT_LIST_DIR}/ai_chat.cpp"
)

target_compile_definitions(ai-chat PRIVATE
    GGML_SYSTEM_ARCH=${GGML_SYSTEM_ARCH}
)

target_include_directories(ai-chat PRIVATE
    "${LLAMA_SRC}"
    "${LLAMA_SRC}/common"
    "${LLAMA_SRC}/include"
    "${LLAMA_SRC}/ggml/include"
    "${LLAMA_SRC}/ggml/src"
)

target_link_libraries(ai-chat
    llama
    llama-common
    android
    log
)

# With GGML_BACKEND_DL disabled, explicitly retain the statically-built
# Vulkan backend in libai-chat.so. Otherwise link-time dead stripping can
# leave Android reporting Vulkan support while ggml enumerates CPU only.
if(TARGET ggml-vulkan)
    target_link_libraries(ai-chat PRIVATE ggml-vulkan)
endif()
