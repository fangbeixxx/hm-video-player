#!/bin/bash
# FFmpeg 交叉编译脚本 - 目标平台: HarmonyOS (arm64-v8a / x86_64)
#
# 前置依赖:
#   1. 下载 FFmpeg 源码: https://ffmpeg.org/releases/ffmpeg-7.0.tar.xz
#   2. 安装 HarmonyOS NDK (DevEco Studio 自带)
#   3. 设置环境变量:
#      export OHOS_NDK=/path/to/openharmony/ndk
#
# 用法:
#   ./build_ffmpeg.sh arm64-v8a    # 平板/手机
#   ./build_ffmpeg.sh x86_64       # 模拟器

set -e

# ========== 配置 ==========
FFMPEG_VERSION="7.0"
ARCH=${1:-arm64-v8a}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUILD_DIR="${SCRIPT_DIR}/build_${ARCH}"
OUTPUT_DIR="${SCRIPT_DIR}/../entry/src/main/cpp/libs/ffmpeg"
SRC_DIR="${SCRIPT_DIR}/ffmpeg-${FFMPEG_VERSION}"

# HarmonyOS NDK 路径
OHOS_NDK=${OHOS_NDK:-"/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"}
TOOLCHAIN="${OHOS_NDK}/llvm"
SYSROOT="${OHOS_NDK}/sysroot"

# 根据架构设置编译参数
if [ "$ARCH" = "arm64-v8a" ]; then
    CC_TRIPLE="aarch64-unknown-linux-ohos"
    CLANG_TARGET="aarch64-linux-ohos"
    FF_ARCH="aarch64"
elif [ "$ARCH" = "x86_64" ]; then
    CC_TRIPLE="x86_64-unknown-linux-ohos"
    CLANG_TARGET="x86_64-linux-ohos"
    FF_ARCH="x86_64"
else
    echo "不支持的架构: $ARCH"
    echo "支持: arm64-v8a, x86_64"
    exit 1
fi

if [ -x "${TOOLCHAIN}/bin/${CC_TRIPLE}-clang" ]; then
    CC="${TOOLCHAIN}/bin/${CC_TRIPLE}-clang"
    CXX="${TOOLCHAIN}/bin/${CC_TRIPLE}-clang++"
else
    CC="${TOOLCHAIN}/bin/clang --target=${CLANG_TARGET}"
    CXX="${TOOLCHAIN}/bin/clang++ --target=${CLANG_TARGET}"
fi

echo "============================================"
echo "  FFmpeg ${FFMPEG_VERSION} for HarmonyOS"
echo "  架构: ${ARCH}"
echo "  工具链: ${TOOLCHAIN}"
echo "============================================"

# ========== 下载 FFmpeg 源码 ==========
if [ ! -d "$SRC_DIR" ]; then
    echo ">>> 下载 FFmpeg ${FFMPEG_VERSION}..."
    cd "$SCRIPT_DIR"
    wget -q "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
    rm "ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi

cd "$SRC_DIR"

# ========== 配置 ==========
echo ">>> 配置 FFmpeg..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

"$SRC_DIR/configure" \
    --prefix="${BUILD_DIR}/install" \
    --enable-cross-compile \
    --target-os=linux \
    --arch=${FF_ARCH} \
    --cc="${CC}" \
    --cxx="${CXX}" \
    --ar="${TOOLCHAIN}/bin/llvm-ar" \
    --nm="${TOOLCHAIN}/bin/llvm-nm" \
    --ranlib="${TOOLCHAIN}/bin/llvm-ranlib" \
    --strip="${TOOLCHAIN}/bin/llvm-strip" \
    --sysroot="${SYSROOT}" \
    --extra-cflags="-fPIC -D__MUSL__" \
    --enable-static \
    --disable-shared \
    --disable-doc \
    --disable-programs \
    --disable-everything \
    --enable-pic \
    --disable-asm \
    --enable-small \
    --disable-vulkan \
    --disable-vaapi \
    --disable-vdpau \
    --disable-cuda \
    --disable-cuvid \
    --disable-nvenc \
    \
    --enable-demuxer=matroska \
    --enable-demuxer=mov \
    --enable-demuxer=avi \
    --enable-demuxer=flv \
    --enable-demuxer=mpegts \
    --enable-demuxer=mp3 \
    --enable-demuxer=wav \
    --enable-demuxer=ogg \
    --enable-demuxer=flac \
    --enable-demuxer=concat \
    --enable-demuxer=data \
    --enable-demuxer=mpegps \
    --enable-demuxer=mpegvideo \
    \
    --enable-decoder=h264 \
    --enable-decoder=hevc \
    --enable-decoder=mpeg4 \
    --enable-decoder=vp8 \
    --enable-decoder=vp9 \
    --enable-decoder=av1 \
    --enable-decoder=mpeg1video \
    --enable-decoder=mpeg2video \
    --enable-decoder=theora \
    --enable-decoder=aac \
    --enable-decoder=ac3 \
    --enable-decoder=eac3 \
    --enable-decoder=mp3 \
    --enable-decoder=opus \
    --enable-decoder=vorbis \
    --enable-decoder=flac \
    --enable-decoder=pcm_s16le \
    --enable-decoder=pcm_s16be \
    --enable-decoder=pcm_f32le \
    --enable-decoder=dca \
    --enable-decoder=pcm_s24le \
    \
    --enable-parser=h264 \
    --enable-parser=hevc \
    --enable-parser=mpeg4video \
    --enable-parser=vp8 \
    --enable-parser=vp9 \
    --enable-parser=av1 \
    --enable-parser=mpegaudio \
    --enable-parser=aac \
    --enable-parser=ac3 \
    --enable-parser=opus \
    --enable-parser=vorbis \
    --enable-parser=flac \
    \
    --enable-protocol=file \
    --enable-protocol=http \
    --enable-protocol=https \
    --enable-protocol=hls \
    --enable-protocol=tcp \
    --enable-protocol=udp \
    --enable-protocol=tls \
    --enable-protocol=concat \
    --enable-protocol=applehttp \
    \
    --enable-swscale \
    --enable-swresample \
    \
    --enable-filter=aresample \
    --enable-filter=scale \
    --enable-filter=format \
    \
    || { echo "配置失败"; exit 1; }

# ========== 编译 ==========
echo ">>> 编译 FFmpeg..."
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
make -j${NPROC}
make install

# ========== 复制产物 ==========
echo ">>> 复制编译结果..."
mkdir -p "${OUTPUT_DIR}/include"
mkdir -p "${OUTPUT_DIR}/lib/${ARCH}"

cp -r "${BUILD_DIR}/install/include/"* "${OUTPUT_DIR}/include/"
cp "${BUILD_DIR}/install/lib/"*.a "${OUTPUT_DIR}/lib/${ARCH}/"

echo ""
echo "============================================"
echo "  编译完成!"
echo "  头文件: ${OUTPUT_DIR}/include/"
echo "  库文件: ${OUTPUT_DIR}/lib/${ARCH}/"
echo "============================================"
echo ""
ls -lh "${OUTPUT_DIR}/lib/${ARCH}/"
