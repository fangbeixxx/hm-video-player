#pragma once

#include <string>
#include <functional>
#include <memory>
#include <thread>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <queue>
#include <condition_variable>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/time.h>
}

#include <native_window/external_window.h>
#include <hilog/log.h>

#undef LOG_TAG
#define LOG_TAG "FFmpegDecoder"

/**
 * 解码后的视频帧
 */
struct VideoFrame {
    uint8_t* data[4];       // YUV 平面数据
    int linesize[4];        // 每行字节数
    int width;
    int height;
    int64_t pts;            // 显示时间戳（微秒）
    AVPixelFormat format;
};

/**
 * 解码后的音频帧
 */
struct AudioFrame {
    uint8_t* data;
    int size;
    int64_t pts;
    int sampleRate;
    int channels;
    int sampleFormat;
};

/**
 * 播放状态回调
 */
struct DecoderCallbacks {
    std::function<void(int width, int height, double duration)> onPrepared;
    std::function<void(const VideoFrame& frame)> onVideoFrame;
    std::function<void(const AudioFrame& frame)> onAudioFrame;
    std::function<void(double currentTime)> onProgress;
    std::function<void()> onCompleted;
    std::function<void(const std::string& error)> onError;
    std::function<void(bool buffering)> onBuffering;
};

/**
 * FFmpeg 解码器核心
 * 支持所有主流视频/音频格式的软解码
 */
class FFmpegDecoder {
public:
    FFmpegDecoder();
    ~FFmpegDecoder();

    // 禁止拷贝
    FFmpegDecoder(const FFmpegDecoder&) = delete;
    FFmpegDecoder& operator=(const FFmpegDecoder&) = delete;

    /**
     * 设置回调
     */
    void setCallbacks(const DecoderCallbacks& callbacks);

    /**
     * 打开媒体文件
     * @param path 文件路径或URL
     * @return 是否成功
     */
    bool open(const std::string& path);

    /**
     * 关闭并释放资源
     */
    void close();

    /**
     * 播放
     */
    void play();

    /**
     * 暂停
     */
    void pause();

    /**
     * 停止
     */
    void stop();

    /**
     * 跳转到指定时间
     * @param timeSec 时间（秒）
     */
    void seek(double timeSec);

    /**
     * 设置播放速度
     * @param speed 速度倍数 (0.5, 0.75, 1.0, 1.25, 1.5, 2.0)
     */
    void setSpeed(double speed);

    /**
     * 设置音量
     * @param volume 0.0 ~ 1.0
     */
    void setVolume(double volume);

    /**
     * 设置渲染窗口
     * @param window NativeWindow 指针
     */
    void setNativeWindow(OHNativeWindow* window);
    void setSurfaceId(uint64_t surfaceId);

    /**
     * 是否正在播放
     */
    bool isPlaying() const;

    /**
     * 是否已暂停
     */
    bool isPaused() const;

    /**
     * 获取视频宽度
     */
    int getWidth() const;

    /**
     * 获取视频高度
     */
    int getHeight() const;

    /**
     * 获取时长（秒）
     */
    double getDuration() const;

    /**
     * 获取当前时间（秒）
     */
    double getCurrentTime() const;

    /**
     * 获取视频编码格式名称
     */
    std::string getVideoCodecName() const;

    /**
     * 获取音频编码格式名称
     */
    std::string getAudioCodecName() const;

private:
    bool ensureNativeWindowLocked(bool forceRecreate);
    void releaseNativeWindowLocked();
    void configureNativeWindowLocked();

    // 打开输入流
    bool openInput(const std::string& path);

    // 查找流信息
    bool findStreams();

    // 打开解码器
    bool openCodecs();

    // 视频解码线程
    void videoDecodeLoop();

    // 音频解码线程
    void audioDecodeLoop();

    // 渲染线程
    void renderLoop();

    // 解码单个视频包
    bool decodeVideoPacket(AVPacket* packet, AVFrame* frame);

    // 解码单个音频包
    bool decodeAudioPacket(AVPacket* packet, AVFrame* frame);

    // 渲染视频帧到 NativeWindow
    bool renderToWindow(const VideoFrame& frame);

    // 转换像素格式到 NV21/NV12（Android/HarmonyOS 常用）
    bool convertFrame(AVFrame* srcFrame, uint8_t* dstData[4], int dstLinesize[4]);

    // 音频重采样
    bool resampleAudio(AVFrame* srcFrame, uint8_t** dstData, int* dstSize);

    // 同步时钟
    void syncClock(int64_t pts);

    // ========== FFmpeg 核心对象 ==========
    AVFormatContext* formatCtx_ = nullptr;
    AVCodecContext* videoCodecCtx_ = nullptr;
    AVCodecContext* audioCodecCtx_ = nullptr;
    SwsContext* swsCtx_ = nullptr;
    SwrContext* swrCtx_ = nullptr;

    // 流索引
    int videoStreamIdx_ = -1;
    int audioStreamIdx_ = -1;

    // ========== 线程 ==========
    std::thread videoThread_;
    std::thread audioThread_;
    std::thread renderThread_;

    // ========== 状态 ==========
    std::atomic<bool> running_{false};
    std::atomic<bool> playing_{false};
    std::atomic<bool> paused_{false};
    std::atomic<bool> seeking_{false};
    std::atomic<double> seekTarget_{0.0};
    std::atomic<double> speed_{1.0};
    std::atomic<double> volume_{1.0};

    // ========== 同步 ==========
    std::mutex videoMtx_;
    std::mutex audioMtx_;
    std::condition_variable videoCv_;
    std::condition_variable audioCv_;

    // 帧队列
    std::queue<AVFrame*> videoFrameQueue_;
    std::queue<AVFrame*> audioFrameQueue_;
    static constexpr int MAX_QUEUE_SIZE = 30;

    // ========== 时钟 ==========
    double videoClock_ = 0.0;
    double audioClock_ = 0.0;
    double masterClock_ = 0.0;
    double startTime_ = 0.0;

    // ========== 渲染 ==========
    std::mutex windowMtx_;
    uint64_t surfaceId_ = 0;
    OHNativeWindow* nativeWindow_ = nullptr;
    uint8_t* yuvBuffer_ = nullptr;
    int yuvBufferSize_ = 0;
    uint8_t* rgbaBuffer_ = nullptr;
    int rgbaBufferSize_ = 0;
    int renderWidth_ = 0;
    int renderHeight_ = 0;
    bool useRgba_ = false;
    bool nativeWindowConfigured_ = false;
    bool ownsNativeWindow_ = false;
    int consecutiveRequestFails_ = 0;
    std::atomic<bool> firstFrameRendered_{false};

    // ========== 音频缓冲 ==========
    uint8_t* audioBuffer_ = nullptr;
    int audioBufferSize_ = 0;
    int audioBufferIndex_ = 0;

    // ========== 回调 ==========
    DecoderCallbacks callbacks_;

    // ========== 辅助 ==========
    std::string filePath_;
    double duration_ = 0.0;

    // AVRational helpers
    AVRational videoTimeBase_{0, 1};
    AVRational audioTimeBase_{0, 1};
};
