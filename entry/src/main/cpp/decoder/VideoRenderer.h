#pragma once

#include <cstdint>

/**
 * 视频渲染器 - NativeWindow 渲染封装
 * 将 YUV 数据渲染到 HarmonyOS 的 NativeWindow 上
 */
class VideoRenderer {
public:
    VideoRenderer();
    ~VideoRenderer();

    /**
     * 设置渲染目标
     */
    void setWindow(void* window, int width, int height);

    /**
     * 渲染一帧 NV12 数据
     */
    bool render(const uint8_t* yData, const uint8_t* uvData,
                int yStride, int uvStride, int width, int height);

    /**
     * 清空画面
     */
    void clear();

    /**
     * 释放资源
     */
    void release();

private:
    void* window_ = nullptr;
    int width_ = 0;
    int height_ = 0;
};
