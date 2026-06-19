cmake_minimum_required(VERSION 3.16)
project(harmonyos-video-player)

set(CMAKE_CXX_STANDARD 17)

set(FFMPEG_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/libs/ffmpeg/include)
set(FFMPEG_LIB_DIR ${CMAKE_SOURCE_DIR}/libs/ffmpeg/lib/${OHOS_ARCH})

set(SOURCES
    decoder/FFmpegDecoder.cpp
    decoder/VideoRenderer.cpp
    decoder/AudioDecoder.cpp
    utils/MediaUtils.cpp
    napi/native_module.cpp
    napi/decoder_napi.cpp
)

add_library(harmonyos-video-player SHARED ${SOURCES})

target_include_directories(harmonyos-video-player PRIVATE
    ${FFMPEG_INCLUDE_DIR}
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/decoder
    ${CMAKE_SOURCE_DIR}/utils
)

target_link_libraries(harmonyos-video-player PRIVATE
    ${FFMPEG_LIB_DIR}/libavformat.a
    ${FFMPEG_LIB_DIR}/libavcodec.a
    ${FFMPEG_LIB_DIR}/libavutil.a
    ${FFMPEG_LIB_DIR}/libswscale.a
    ${FFMPEG_LIB_DIR}/libswresample.a
    ${FFMPEG_LIB_DIR}/libavfilter.a
)

target_link_libraries(harmonyos-video-player PRIVATE
    libace_napi.z.so
    libace_ndk.z.so
    libnative_window.so
    libhilog_ndk.z.so
    libnative_drawing.so
    libohaudio.so
    libohimage.so
    libz.so
    libm.so
)
