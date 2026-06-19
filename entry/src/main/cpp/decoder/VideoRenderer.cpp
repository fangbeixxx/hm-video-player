#include "VideoRenderer.h"
#include <native_window/external_window.h>
#include <native_buffer/native_buffer.h>
#include <cstring>

VideoRenderer::VideoRenderer() = default;

VideoRenderer::~VideoRenderer() {
    release();
}

void VideoRenderer::setWindow(void* window, int width, int height) {
    window_ = window;
    width_ = width;
    height_ = height;

    if (window_) {
        OH_NativeWindow_NativeWindowHandleOpt(
            (OHNativeWindow*)window_, SET_BUFFER_GEOMETRY, width, height);
    }
}

bool VideoRenderer::render(const uint8_t* yData, const uint8_t* uvData,
                            int yStride, int uvStride, int width, int height) {
    if (!window_) return false;

    OHNativeWindow* nativeWin = (OHNativeWindow*)window_;
    OHNativeWindowBuffer* windowBuffer = nullptr;

    int ret = OH_NativeWindow_NativeWindowRequestBuffer(nativeWin, &windowBuffer, nullptr);
    if (ret != 0 || !windowBuffer) return false;

    BufferHandle* handle = OH_NativeWindow_GetBufferHandleFromNative(windowBuffer);
    if (!handle) {
        Region emptyRegion = {nullptr, 0};
        OH_NativeWindow_NativeWindowFlushBuffer(nativeWin, windowBuffer, -1, emptyRegion);
        return false;
    }
    void* bufferAddr = handle->virAddr;

    uint8_t* dst = (uint8_t*)bufferAddr;
    int ySize = width * height;

    // 拷贝 Y 平面
    for (int i = 0; i < height; i++) {
        memcpy(dst + i * width, yData + i * yStride, width);
    }
    // 拷贝 UV 平面
    for (int i = 0; i < height / 2; i++) {
        memcpy(dst + ySize + i * width, uvData + i * uvStride, width);
    }

    Region region = {nullptr, 0};
    OH_NativeWindow_NativeWindowFlushBuffer(nativeWin, windowBuffer, -1, region);
    return true;
}

void VideoRenderer::clear() {
    if (!window_) return;

    OHNativeWindow* nativeWin = (OHNativeWindow*)window_;
    OHNativeWindowBuffer* windowBuffer = nullptr;

    if (OH_NativeWindow_NativeWindowRequestBuffer(nativeWin, &windowBuffer, nullptr) == 0
        && windowBuffer) {
        BufferHandle* handle = OH_NativeWindow_GetBufferHandleFromNative(windowBuffer);
        if (handle && handle->virAddr) {
            int size = width_ * height_ * 3 / 2;
            memset(handle->virAddr, 0, size);
        }
        Region region = {nullptr, 0};
        OH_NativeWindow_NativeWindowFlushBuffer(nativeWin, windowBuffer, -1, region);
    }
}

void VideoRenderer::release() {
    window_ = nullptr;
    width_ = 0;
    height_ = 0;
}
