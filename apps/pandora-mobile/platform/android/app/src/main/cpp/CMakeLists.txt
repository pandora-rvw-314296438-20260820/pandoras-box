cmake_minimum_required(VERSION 3.31.6)

project("ai-chat" VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED true)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED true)

if(NOT DEFINED ANDROID_ABI OR NOT ANDROID_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "Pandora local AI currently supports arm64-v8a only")
endif()

set(GGML_SYSTEM_ARCH "ARM")
set(GGML_CPU_KLEIDIAI ON)
set(GGML_OPENMP ON)

set(LLAMA_SRC "${CMAKE_CURRENT_LIST_DIR}/../../../../llama.cpp")
if(NOT EXISTS "${LLAMA_SRC}/CMakeLists.txt")
    message(FATAL_ERROR "Pinned llama.cpp source is missing from android/llama.cpp")
endif()

add_subdirectory("${LLAMA_SRC}" build-llama)

add_library(ai-chat SHARED
    "${CMAKE_CURRENT_LIST_DIR}/ai_chat.cpp"
)

target_compile_definitions(ai-chat PRIVATE
    GGML_SYSTEM_ARCH=${GGML_SYSTEM_ARCH}
    GGML_CPU_KLEIDIAI=$<BOOL:${GGML_CPU_KLEIDIAI}>
    GGML_OPENMP=$<BOOL:${GGML_OPENMP}>
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
