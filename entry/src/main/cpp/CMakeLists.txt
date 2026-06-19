cmake_minimum_required(VERSION 3.16)
project(harmonyos-video-player)

set(CMAKE_CXX_STANDARD 17)

# FFmpeg 头文件路径（编译后放在 libs/ffmpeg/include）
set(FFMPEG_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/libs/ffmpeg/include)

# FFmpeg 库文件路径
set(FFMPEG_LIB_DIR ${CMAKE_SOURCE_DIR}/libs/ffmpeg/lib/${OHOS_ARCH})

# 源文件
set(SOURCES
    src/main/cpp/decoder/FFmpegDecoder.cpp
    src/main/cpp/decoder/VideoRenderer.cpp
    src/main/cpp/decoder/AudioDecoder.cpp
    src/main/cpp/utils/MediaUtils.cpp
    src/main/cpp/napi/native_module.cpp
    src/main/cpp/napi/decoder_napi.cpp
)

# 构建共享库
add_library(harmonyos-video-player SHARED ${SOURCES})

# 头文件包含
target_include_directories(harmonyos-video-player PRIVATE
    ${FFMPEG_INCLUDE_DIR}
    ${CMAKE_SOURCE_DIR}/src/main/cpp
    ${CMAKE_SOURCE_DIR}/src/main/cpp/decoder
    ${CMAKE_SOURCE_DIR}/src/main/cpp/utils
)

# 链接 FFmpeg 库
target_link_libraries(harmonyos-video-player PRIVATE
    ${FFMPEG_LIB_DIR}/libavformat.a
    ${FFMPEG_LIB_DIR}/libavcodec.a
    ${FFMPEG_LIB_DIR}/libavutil.a
    ${FFMPEG_LIB_DIR}/libswscale.a
    ${FFMPEG_LIB_DIR}/libswresample.a
    ${FFMPEG_LIB_DIR}/libavfilter.a
)

# 链接 HarmonyOS NDK 库
target_link_libraries(harmonyos-video-player PRIVATE
    libace_napi.z.so
    libace_ndk.z.so
    libnative_window.z.so
    libhilog_ndk.z.so
    libnative_drawing.z.so
    libohaudio.z.so
    libohimage.z.so
    libz.so
    libm.so
    liblog.so
)
