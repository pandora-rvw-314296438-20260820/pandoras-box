cmake_minimum_required(VERSION 3.22.1)

project(pandora_vulkan_benchmark LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN ON CACHE BOOL "" FORCE)
set(GGML_VULKAN_CHECK_RESULTS OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_SUBPROCESS OFF CACHE BOOL "" FORCE)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp source missing. Codespace builder must clone the exact upstream SHA before Gradle build.")
endif()

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/vulkan-headers/include/vulkan/vulkan.hpp")
    message(FATAL_ERROR "Vulkan C++ headers missing. Codespace builder must stage vulkan.hpp before Gradle build.")
endif()

include_directories(SYSTEM "${CMAKE_CURRENT_SOURCE_DIR}/vulkan-headers/include")

add_subdirectory(llama.cpp llama-build)

find_package(Threads REQUIRED)

add_library(pandora_llama_bench_impl STATIC
    llama.cpp/tools/llama-bench/llama-bench.cpp
)
set_target_properties(pandora_llama_bench_impl PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(pandora_llama_bench_impl PUBLIC
    llama.cpp/tools/llama-bench
)

target_link_libraries(pandora_llama_bench_impl PUBLIC
    llama-common
    llama
    Threads::Threads
)

add_library(pandora_bench SHARED
    bench_jni.cpp
)

target_compile_options(pandora_bench PRIVATE -O3)

target_include_directories(pandora_bench PRIVATE
    llama.cpp/include
    llama.cpp/ggml/include
)

target_link_libraries(pandora_bench PRIVATE
    pandora_llama_bench_impl
    android
    log
)
