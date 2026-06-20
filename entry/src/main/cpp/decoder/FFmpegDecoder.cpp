#include "FFmpegDecoder.h"
#include <cstring>
#include <algorithm>
#include <native_buffer/native_buffer.h>

// 兼容定义：如果 SDK 头文件未提供以下常量，使用标准值
#ifndef SET_USAGE
#define SET_USAGE 0x1001
#endif
#ifndef SET_BUFFER_QUEUE_SIZE
#define SET_BUFFER_QUEUE_SIZE 0x1008
#endif
#ifndef NATIVEBUFFER_USAGE_CPU_READ
#define NATIVEBUFFER_USAGE_CPU_READ 0x00000001
#endif
#ifndef NATIVEBUFFER_USAGE_CPU_WRITE
#define NATIVEBUFFER_USAGE_CPU_WRITE 0x00000002
#endif
#ifndef NATIVEBUFFER_USAGE_HW_RENDER
#define NATIVEBUFFER_USAGE_HW_RENDER 0x00000010
#endif
// NV12 像素格式值 (GRAPHIC_PIXEL_FMT_YCBCR_420_SP = 3)
#ifndef NV12_FORMAT_VALUE
#define NV12_FORMAT_VALUE 3
#endif
// RGBA 像素格式值 (GRAPHIC_PIXEL_FMT_RGBA_8888 = 0)
#ifndef RGBA_FORMAT_VALUE
#define RGBA_FORMAT_VALUE 0
#endif

// HarmonyOS HiLog
static constexpr unsigned int APP_LOG_DOMAIN = 0x0201;
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, APP_LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGW(...) OH_LOG_Print(LOG_APP, LOG_WARN, APP_LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

// ========== 构造/析构 ==========

FFmpegDecoder::FFmpegDecoder() {
    audioBuffer_ = new uint8_t[192000]; // 足够大的音频缓冲
    audioBufferSize_ = 0;
    audioBufferIndex_ = 0;
}

FFmpegDecoder::~FFmpegDecoder() {
    close();
    delete[] audioBuffer_;
}

void FFmpegDecoder::setCallbacks(const DecoderCallbacks& callbacks) {
    callbacks_ = callbacks;
}

// ========== 打开/关闭 ==========

bool FFmpegDecoder::open(const std::string& path) {
    filePath_ = path;
    LOGI("Opening: %{public}s", path.c_str());

    if (!openInput(path)) return false;
    if (!findStreams()) return false;
    if (!openCodecs()) return false;

    // 计算时长
    duration_ = formatCtx_->duration / (double)AV_TIME_BASE;
    int width = videoCodecCtx_ ? videoCodecCtx_->width : 0;
    int height = videoCodecCtx_ ? videoCodecCtx_->height : 0;

    LOGI("Prepared: %dx%d, duration=%.2fs", width, height, duration_);
    if (callbacks_.onPrepared) {
        callbacks_.onPrepared(width, height, duration_);
    }
    return true;
}

void FFmpegDecoder::close() {
    running_ = false;
    playing_ = false;

    // 唤醒等待的线程
    videoCv_.notify_all();
    audioCv_.notify_all();

    if (videoThread_.joinable()) videoThread_.join();
    if (audioThread_.joinable()) audioThread_.join();
    if (renderThread_.joinable()) renderThread_.join();

    {
        std::lock_guard<std::mutex> lock(windowMtx_);
        releaseNativeWindowLocked();
    }

    // 清空队列
    {
        std::lock_guard<std::mutex> lock(videoMtx_);
        while (!videoFrameQueue_.empty()) {
            av_frame_free(&videoFrameQueue_.front());
            videoFrameQueue_.pop();
        }
    }
    {
        std::lock_guard<std::mutex> lock(audioMtx_);
        while (!audioFrameQueue_.empty()) {
            av_frame_free(&audioFrameQueue_.front());
            audioFrameQueue_.pop();
        }
    }

    // 释放 FFmpeg 对象
    if (swsCtx_) { sws_freeContext(swsCtx_); swsCtx_ = nullptr; }
    if (swrCtx_) { swr_free(&swrCtx_); }
    if (videoCodecCtx_) { avcodec_free_context(&videoCodecCtx_); }
    if (audioCodecCtx_) { avcodec_free_context(&audioCodecCtx_); }
    if (formatCtx_) { avformat_close_input(&formatCtx_); }

    if (yuvBuffer_) {
        av_free(yuvBuffer_);
        yuvBuffer_ = nullptr;
    }
    if (rgbaBuffer_) {
        av_free(rgbaBuffer_);
        rgbaBuffer_ = nullptr;
    }

    videoStreamIdx_ = -1;
    audioStreamIdx_ = -1;
    videoClock_ = 0;
    audioClock_ = 0;
    masterClock_ = 0;
    consecutiveRequestFails_ = 0;
    renderWidth_ = 0;
    renderHeight_ = 0;
    useRgba_ = false;
    nativeWindowConfigured_ = false;
    firstFrameRendered_ = false;
}

// ========== 内部初始化 ==========

bool FFmpegDecoder::openInput(const std::string& path) {
    formatCtx_ = avformat_alloc_context();
    if (!formatCtx_) {
        LOGE("Failed to alloc format context");
        return false;
    }

    // 超时设置
    AVDictionary* opts = nullptr;
    av_dict_set(&opts, "timeout", "10000000", 0); // 10秒超时
    av_dict_set(&opts, "reconnect", "1", 0);
    av_dict_set(&opts, "user_agent", "HarmonyOS-VideoPlayer/1.0", 0);

    int ret = avformat_open_input(&formatCtx_, path.c_str(), nullptr, &opts);
    av_dict_free(&opts);

    if (ret < 0) {
        char errBuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errBuf, sizeof(errBuf));
        LOGE("Failed to open input: %{public}s", errBuf);
        if (callbacks_.onError) {
            callbacks_.onError(std::string("无法打开文件: ") + errBuf);
        }
        return false;
    }

    return true;
}

bool FFmpegDecoder::findStreams() {
    if (avformat_find_stream_info(formatCtx_, nullptr) < 0) {
        LOGE("Failed to find stream info");
        if (callbacks_.onError) {
            callbacks_.onError("无法读取媒体信息");
        }
        return false;
    }

    // 查找最佳视频流
    videoStreamIdx_ = av_find_best_stream(formatCtx_, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (videoStreamIdx_ < 0) {
        LOGW("No video stream found (audio-only file)");
    }

    // 查找最佳音频流
    audioStreamIdx_ = av_find_best_stream(formatCtx_, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (audioStreamIdx_ < 0) {
        LOGW("No audio stream found");
    }

    if (videoStreamIdx_ < 0 && audioStreamIdx_ < 0) {
        LOGE("No audio or video stream found");
        if (callbacks_.onError) {
            callbacks_.onError("未找到音视频流");
        }
        return false;
    }

    return true;
}

bool FFmpegDecoder::openCodecs() {
    // 打开视频解码器
    if (videoStreamIdx_ >= 0) {
        AVStream* stream = formatCtx_->streams[videoStreamIdx_];
        const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
        if (!codec) {
            LOGE("Video codec not found for id: %{public}d", stream->codecpar->codec_id);
            // 不阻断，可能只有音频
        } else {
            videoCodecCtx_ = avcodec_alloc_context3(codec);
            avcodec_parameters_to_context(videoCodecCtx_, stream->codecpar);

            // 多线程解码
            videoCodecCtx_->thread_count = 4;
            videoCodecCtx_->thread_type = FF_THREAD_FRAME;

            if (avcodec_open2(videoCodecCtx_, codec, nullptr) < 0) {
                LOGE("Failed to open video codec: %{public}s", codec->name);
                avcodec_free_context(&videoCodecCtx_);
                videoCodecCtx_ = nullptr;
            } else {
                videoTimeBase_ = stream->time_base;
                LOGI("Video codec: %{public}s, %dx%d",
                     codec->name, videoCodecCtx_->width, videoCodecCtx_->height);
            }
        }
    }

    // 打开音频解码器
    if (audioStreamIdx_ >= 0) {
        AVStream* stream = formatCtx_->streams[audioStreamIdx_];
        const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
        if (!codec) {
            LOGE("Audio codec not found for id: %{public}d", stream->codecpar->codec_id);
        } else {
            audioCodecCtx_ = avcodec_alloc_context3(codec);
            avcodec_parameters_to_context(audioCodecCtx_, stream->codecpar);

            if (avcodec_open2(audioCodecCtx_, codec, nullptr) < 0) {
                LOGE("Failed to open audio codec: %{public}s", codec->name);
                avcodec_free_context(&audioCodecCtx_);
                audioCodecCtx_ = nullptr;
            } else {
                audioTimeBase_ = stream->time_base;
                LOGI("Audio codec: %{public}s, %{public}dch, %{public}dHz",
                     codec->name, audioCodecCtx_->ch_layout.nb_channels, audioCodecCtx_->sample_rate);
            }
        }
    }

    // 初始化 SWS（像素格式转换，默认输出 NV12，后续可按实际 buffer 格式切换到 RGBA）
    if (videoCodecCtx_) {
        swsCtx_ = sws_getContext(
            videoCodecCtx_->width, videoCodecCtx_->height, videoCodecCtx_->pix_fmt,
            videoCodecCtx_->width, videoCodecCtx_->height, AV_PIX_FMT_NV12,
            SWS_BILINEAR, nullptr, nullptr, nullptr
        );

        if (!swsCtx_) {
            LOGE("Failed to create SWS context");
        }

        // 分配 YUV 缓冲
        renderWidth_ = videoCodecCtx_->width;
        renderHeight_ = videoCodecCtx_->height;
        yuvBufferSize_ = av_image_get_buffer_size(AV_PIX_FMT_NV12,
            renderWidth_, renderHeight_, 1);
        yuvBuffer_ = yuvBufferSize_ > 0 ? (uint8_t*)av_malloc(yuvBufferSize_) : nullptr;
    }

    // 初始化 SWR（音频重采样）
    if (audioCodecCtx_) {
        AVChannelLayout inLayout = {};
        if (audioCodecCtx_->ch_layout.nb_channels > 0 &&
            av_channel_layout_check(&audioCodecCtx_->ch_layout)) {
            av_channel_layout_copy(&inLayout, &audioCodecCtx_->ch_layout);
        } else {
            av_channel_layout_default(&inLayout, 2);
        }

        AVChannelLayout outLayout = {};
        av_channel_layout_copy(&outLayout, &inLayout);

        int ret = swr_alloc_set_opts2(
            &swrCtx_,
            &outLayout, AV_SAMPLE_FMT_S16, audioCodecCtx_->sample_rate,
            &inLayout, audioCodecCtx_->sample_fmt, audioCodecCtx_->sample_rate,
            0, nullptr);

        av_channel_layout_uninit(&outLayout);
        av_channel_layout_uninit(&inLayout);

        if (ret < 0 || !swrCtx_ || swr_init(swrCtx_) < 0) {
            LOGE("Failed to init SWR context");
            swr_free(&swrCtx_);
            swrCtx_ = nullptr;
        }
    }

    return true;
}

// ========== 播放控制 ==========

void FFmpegDecoder::play() {
    if (running_ && !paused_ && playing_) return;

    const double now = av_gettime() / 1000000.0;

    if (running_ && paused_) {
        paused_ = false;
        playing_ = true;
        startTime_ = now - masterClock_;
        videoCv_.notify_all();
        audioCv_.notify_all();
        LOGI("Playback resumed");
        return;
    }

    running_ = true;
    playing_ = true;
    paused_ = false;
    firstFrameRendered_ = false;

    if (!videoThread_.joinable() && videoCodecCtx_) {
        videoThread_ = std::thread(&FFmpegDecoder::videoDecodeLoop, this);
        renderThread_ = std::thread(&FFmpegDecoder::renderLoop, this);
    }
    // Audio output is not bridged into ArkTS yet. Starting a second demux thread
    // on the same AVFormatContext can race with videoDecodeLoop and crash the app.
    // Keep FFmpeg fallback video-only until a single-threaded demux pipeline exists.

    startTime_ = now - masterClock_;
    videoCv_.notify_all();
    audioCv_.notify_all();
    LOGI("Playback started");
}

void FFmpegDecoder::pause() {
    if (!running_ || paused_) {
        return;
    }

    paused_ = true;
    playing_ = false;
    LOGI("Playback paused");
}

void FFmpegDecoder::stop() {
    running_ = false;
    playing_ = false;
    paused_ = false;
    videoCv_.notify_all();
    audioCv_.notify_all();
    LOGI("Playback stopped");
}

void FFmpegDecoder::seek(double timeSec) {
    seekTarget_ = timeSec;
    seeking_ = true;

    // 清空队列
    {
        std::lock_guard<std::mutex> lock(videoMtx_);
        while (!videoFrameQueue_.empty()) {
            av_frame_free(&videoFrameQueue_.front());
            videoFrameQueue_.pop();
        }
    }
    {
        std::lock_guard<std::mutex> lock(audioMtx_);
        while (!audioFrameQueue_.empty()) {
            av_frame_free(&audioFrameQueue_.front());
            audioFrameQueue_.pop();
        }
    }

    int64_t timestamp = (int64_t)(timeSec * AV_TIME_BASE);
    avformat_seek_file(formatCtx_, -1, INT64_MIN, timestamp, INT64_MAX, 0);

    videoClock_ = timeSec;
    audioClock_ = timeSec;
    seeking_ = false;

    videoCv_.notify_all();
    audioCv_.notify_all();

    LOGI("Seek to: %{public}.2f", timeSec);
}

void FFmpegDecoder::setSpeed(double speed) {
    speed_ = std::clamp(speed, 0.5, 4.0);
}

void FFmpegDecoder::setVolume(double volume) {
    volume_ = std::clamp(volume, 0.0, 1.0);
}

void FFmpegDecoder::setNativeWindow(OHNativeWindow* window) {
    std::lock_guard<std::mutex> lock(windowMtx_);

    if (nativeWindow_ == window) {
        return;
    }

    surfaceId_ = 0;
    consecutiveRequestFails_ = 0;
    nativeWindowConfigured_ = false;
    firstFrameRendered_ = false;
    releaseNativeWindowLocked();
    nativeWindow_ = window;
    ownsNativeWindow_ = false;
}

void FFmpegDecoder::setSurfaceId(uint64_t surfaceId) {
    std::lock_guard<std::mutex> lock(windowMtx_);

    if (surfaceId_ == surfaceId) {
        return;
    }

    surfaceId_ = surfaceId;
    consecutiveRequestFails_ = 0;
    nativeWindowConfigured_ = false;
    firstFrameRendered_ = false;
    releaseNativeWindowLocked();
}

bool FFmpegDecoder::ensureNativeWindowLocked(bool forceRecreate) {
    if (forceRecreate) {
        releaseNativeWindowLocked();
    }

    if (nativeWindow_ != nullptr) {
        return true;
    }

    if (surfaceId_ == 0) {
        return false;
    }

    OHNativeWindow* window = nullptr;
    int32_t ret = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId_, &window);
    if (ret != 0 || window == nullptr) {
        LOGW("CreateNativeWindowFromSurfaceId failed: ret=%{public}d surfaceId=%{public}llu",
             ret, static_cast<unsigned long long>(surfaceId_));
        nativeWindow_ = nullptr;
        return false;
    }

    nativeWindow_ = window;
    ownsNativeWindow_ = true;
    consecutiveRequestFails_ = 0;
    nativeWindowConfigured_ = false;
    return true;
}

void FFmpegDecoder::releaseNativeWindowLocked() {
    if (nativeWindow_ != nullptr) {
        if (ownsNativeWindow_) {
            OH_NativeWindow_DestroyNativeWindow(nativeWindow_);
        }
        nativeWindow_ = nullptr;
    }

    ownsNativeWindow_ = false;
    nativeWindowConfigured_ = false;
}

void FFmpegDecoder::configureNativeWindowLocked() {
    if (videoCodecCtx_ == nullptr || !ensureNativeWindowLocked(false)) {
        return;
    }

    OHNativeWindowBuffer* probeBuffer = nullptr;
    int probeRet = OH_NativeWindow_NativeWindowRequestBuffer(nativeWindow_, &probeBuffer, nullptr);

    if (probeRet != 0 || !probeBuffer) {
        LOGW("Probe RequestBuffer (no config): %{public}d, trying SET_USAGE", probeRet);

        uint64_t usage = NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_WRITE |
                         NATIVEBUFFER_USAGE_HW_RENDER;
        OH_NativeWindow_NativeWindowHandleOpt(nativeWindow_, SET_USAGE, usage);
        OH_NativeWindow_NativeWindowHandleOpt(nativeWindow_, SET_BUFFER_QUEUE_SIZE, 8);

        probeRet = OH_NativeWindow_NativeWindowRequestBuffer(nativeWindow_, &probeBuffer, nullptr);
    }

    if (probeRet != 0 || !probeBuffer) {
        nativeWindowConfigured_ = false;
        LOGE("Probe RequestBuffer still fails: %{public}d even with minimal config", probeRet);
        return;
    }

    BufferHandle* handle = OH_NativeWindow_GetBufferHandleFromNative(probeBuffer);
    if (!handle) {
        Region emptyRegion = {nullptr, 0};
        OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, probeBuffer, -1, emptyRegion);
        nativeWindowConfigured_ = false;
        LOGE("Probe: cannot get buffer handle");
        return;
    }

    const int actualFormat = handle->format;
    renderWidth_ = handle->width > 0 ? handle->width : videoCodecCtx_->width;
    renderHeight_ = handle->height > 0 ? handle->height : videoCodecCtx_->height;

    AVPixelFormat probeDstFormat = AV_PIX_FMT_NV12;

    if (actualFormat == NV12_FORMAT_VALUE) {
        useRgba_ = false;
        probeDstFormat = AV_PIX_FMT_NV12;

        const int requiredSize = av_image_get_buffer_size(AV_PIX_FMT_NV12, renderWidth_, renderHeight_, 1);
        if (requiredSize <= 0) {
            Region emptyRegion = {nullptr, 0};
            OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, probeBuffer, -1, emptyRegion);
            nativeWindowConfigured_ = false;
            LOGE("Failed to size NV12 buffer");
            return;
        }

        if (requiredSize != yuvBufferSize_ || yuvBuffer_ == nullptr) {
            if (yuvBuffer_) {
                av_free(yuvBuffer_);
            }
            yuvBuffer_ = (uint8_t*)av_malloc(requiredSize);
            yuvBufferSize_ = yuvBuffer_ ? requiredSize : 0;
        }

        LOGI("Buffer format: NV12, size=%{public}dx%{public}d", renderWidth_, renderHeight_);
    } else {
        useRgba_ = true;
        probeDstFormat = AV_PIX_FMT_RGBA;

        const int requiredSize = av_image_get_buffer_size(AV_PIX_FMT_RGBA, renderWidth_, renderHeight_, 1);
        if (requiredSize <= 0) {
            Region emptyRegion = {nullptr, 0};
            OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, probeBuffer, -1, emptyRegion);
            nativeWindowConfigured_ = false;
            LOGE("Failed to size RGBA buffer");
            return;
        }

        if (requiredSize != rgbaBufferSize_ || rgbaBuffer_ == nullptr) {
            if (rgbaBuffer_) {
                av_free(rgbaBuffer_);
            }
            rgbaBuffer_ = (uint8_t*)av_malloc(requiredSize);
            rgbaBufferSize_ = rgbaBuffer_ ? requiredSize : 0;
        }

        LOGI("Buffer format: %{public}d (non-NV12), size=%{public}dx%{public}d, will convert to RGBA",
             actualFormat, renderWidth_, renderHeight_);
    }

    if ((!useRgba_ && yuvBuffer_ == nullptr) || (useRgba_ && rgbaBuffer_ == nullptr)) {
        Region emptyRegion = {nullptr, 0};
        OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, probeBuffer, -1, emptyRegion);
        nativeWindowConfigured_ = false;
        LOGE("Failed to allocate render buffer");
        return;
    }

    if (swsCtx_) {
        sws_freeContext(swsCtx_);
        swsCtx_ = nullptr;
    }
    swsCtx_ = sws_getContext(
        videoCodecCtx_->width, videoCodecCtx_->height, videoCodecCtx_->pix_fmt,
        renderWidth_, renderHeight_, probeDstFormat,
        SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (!swsCtx_) {
        nativeWindowConfigured_ = false;
        LOGE("Failed to create SWS context (dst format=%{public}d)", probeDstFormat);
    } else {
        nativeWindowConfigured_ = true;
        consecutiveRequestFails_ = 0;
    }

    Region emptyRegion = {nullptr, 0};
    OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, probeBuffer, -1, emptyRegion);
}

bool FFmpegDecoder::isPlaying() const { return playing_ && !paused_; }
bool FFmpegDecoder::isPaused() const { return paused_; }
int FFmpegDecoder::getWidth() const { return videoCodecCtx_ ? videoCodecCtx_->width : 0; }
int FFmpegDecoder::getHeight() const { return videoCodecCtx_ ? videoCodecCtx_->height : 0; }
double FFmpegDecoder::getDuration() const { return duration_; }
double FFmpegDecoder::getCurrentTime() const { return masterClock_; }

std::string FFmpegDecoder::getVideoCodecName() const {
    if (videoCodecCtx_) return avcodec_get_name(videoCodecCtx_->codec_id);
    return "none";
}

std::string FFmpegDecoder::getAudioCodecName() const {
    if (audioCodecCtx_) return avcodec_get_name(audioCodecCtx_->codec_id);
    return "none";
}

// ========== 视频解码线程 ==========

void FFmpegDecoder::videoDecodeLoop() {
    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();

    while (running_) {
        if (paused_) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        // 队列满时等待
        {
            std::unique_lock<std::mutex> lock(videoMtx_);
            if (videoFrameQueue_.size() >= MAX_QUEUE_SIZE) {
                videoCv_.wait_for(lock, std::chrono::milliseconds(10));
                continue;
            }
        }

        // 读取数据包
        int ret = av_read_frame(formatCtx_, packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF) {
                // 文件读取完毕
                LOGI("End of file reached");
                if (callbacks_.onCompleted) {
                    callbacks_.onCompleted();
                }
                playing_ = false;
                break;
            }
            char errBuf[AV_ERROR_MAX_STRING_SIZE];
            av_strerror(ret, errBuf, sizeof(errBuf));
            LOGE("Read frame error: %{public}s", errBuf);
            continue;
        }

        // 视频包 -> 解码
        if (packet->stream_index == videoStreamIdx_ && videoCodecCtx_) {
            decodeVideoPacket(packet, frame);
        }

        av_packet_unref(packet);
    }

    av_packet_free(&packet);
    av_frame_free(&frame);
    LOGI("Video decode loop ended");
}

bool FFmpegDecoder::decodeVideoPacket(AVPacket* packet, AVFrame* frame) {
    int ret = avcodec_send_packet(videoCodecCtx_, packet);
    if (ret < 0) return false;

    while (ret >= 0) {
        ret = avcodec_receive_frame(videoCodecCtx_, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) break;
        if (ret < 0) return false;

        // 计算 PTS
        double pts = frame->best_effort_timestamp * av_q2d(videoTimeBase_);

        // 克隆帧放入队列
        AVFrame* cloned = av_frame_clone(frame);
        if (!cloned) {
            return false;
        }
        cloned->opaque = new double(pts);

        {
            std::lock_guard<std::mutex> lock(videoMtx_);
            videoFrameQueue_.push(cloned);
            videoCv_.notify_one();
        }
    }
    return true;
}

// ========== 音频解码线程 ==========

void FFmpegDecoder::audioDecodeLoop() {
    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();

    while (running_) {
        if (paused_) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        {
            std::unique_lock<std::mutex> lock(audioMtx_);
            if (audioFrameQueue_.size() >= MAX_QUEUE_SIZE) {
                audioCv_.wait_for(lock, std::chrono::milliseconds(10));
                continue;
            }
        }

        int ret = av_read_frame(formatCtx_, packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF) break;
            continue;
        }

        if (packet->stream_index == audioStreamIdx_ && audioCodecCtx_) {
            decodeAudioPacket(packet, frame);
        }

        av_packet_unref(packet);
    }

    av_packet_free(&packet);
    av_frame_free(&frame);
    LOGI("Audio decode loop ended");
}

bool FFmpegDecoder::decodeAudioPacket(AVPacket* packet, AVFrame* frame) {
    int ret = avcodec_send_packet(audioCodecCtx_, packet);
    if (ret < 0) return false;

    while (ret >= 0) {
        ret = avcodec_receive_frame(audioCodecCtx_, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) break;
        if (ret < 0) return false;

        double pts = frame->best_effort_timestamp * av_q2d(audioTimeBase_);

        // 重采样
        if (swrCtx_) {
            uint8_t* outBuffer = nullptr;
            int outSize = 0;
            if (resampleAudio(frame, &outBuffer, &outSize)) {
                AudioFrame audioFrame;
                audioFrame.data = outBuffer;
                audioFrame.size = outSize;
                audioFrame.pts = (int64_t)(pts * 1000000);
                audioFrame.sampleRate = audioCodecCtx_->sample_rate;
                audioFrame.channels = audioCodecCtx_->ch_layout.nb_channels;

                if (callbacks_.onAudioFrame) {
                    callbacks_.onAudioFrame(audioFrame);
                }
                delete[] outBuffer;
            }
        }
    }
    return true;
}

bool FFmpegDecoder::resampleAudio(AVFrame* srcFrame, uint8_t** dstData, int* dstSize) {
    if (!swrCtx_) return false;

    int outSamples = swr_get_out_samples(swrCtx_, srcFrame->nb_samples);
    int channels = srcFrame->ch_layout.nb_channels > 0
        ? srcFrame->ch_layout.nb_channels
        : audioCodecCtx_->ch_layout.nb_channels;
    int bytesPerSample = 2 * channels; // S16 format
    *dstSize = outSamples * bytesPerSample;
    *dstData = new uint8_t[*dstSize];

    uint8_t* outPtr = *dstData;
    int converted = swr_convert(swrCtx_, &outPtr, outSamples,
        (const uint8_t**)srcFrame->data, srcFrame->nb_samples);

    if (converted < 0) {
        delete[] *dstData;
        *dstData = nullptr;
        return false;
    }

    *dstSize = converted * bytesPerSample;
    return true;
}

// ========== 渲染线程 ==========

void FFmpegDecoder::renderLoop() {
    // 绛夊緟涓€灏忔鏃堕棿锛岀‘淇?XComponent 鐨?SurfaceNode 瀹屽叏鍔犲叆娓叉煋鏍戯紝
    // 涓斿悎鎴愬櫒宸茶繛鎺ュ埌 surface 鐨?buffer 闃熷垪銆?
    std::this_thread::sleep_for(std::chrono::milliseconds(200));

    {
        std::lock_guard<std::mutex> lock(windowMtx_);
        configureNativeWindowLocked();
    }

    while (running_) {
        if (paused_) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        AVFrame* frame = nullptr;
        {
            std::unique_lock<std::mutex> lock(videoMtx_);
            if (videoFrameQueue_.empty()) {
                videoCv_.wait_for(lock, std::chrono::milliseconds(5));
                continue;
            }
            frame = videoFrameQueue_.front();
            videoFrameQueue_.pop();
        }

        if (!frame) continue;

        double pts = *(double*)frame->opaque;
        masterClock_ = pts;

        if (callbacks_.onProgress) {
            callbacks_.onProgress(pts);
        }

        double delay = pts - (av_gettime() / 1000000.0 - startTime_);
        if (delay > 0.005) {
            delay /= speed_.load();
            std::this_thread::sleep_for(
                std::chrono::microseconds((int64_t)(delay * 1000000)));
        }

        if (swsCtx_) {
            const int targetWidth = renderWidth_ > 0 ? renderWidth_ : frame->width;
            const int targetHeight = renderHeight_ > 0 ? renderHeight_ : frame->height;

            if (useRgba_ && rgbaBuffer_) {
                uint8_t* dstData[4] = { rgbaBuffer_, nullptr, nullptr, nullptr };
                int dstLinesize[4] = { targetWidth * 4, 0, 0, 0 };

                sws_scale(swsCtx_, frame->data, frame->linesize, 0,
                    frame->height, dstData, dstLinesize);

                VideoFrame renderFrame{};
                memcpy(renderFrame.data, dstData, sizeof(dstData));
                memcpy(renderFrame.linesize, dstLinesize, sizeof(dstLinesize));
                renderFrame.width = targetWidth;
                renderFrame.height = targetHeight;
                renderFrame.pts = static_cast<int64_t>(pts * 1000000);
                renderFrame.format = AV_PIX_FMT_RGBA;
                renderToWindow(renderFrame);
            } else if (!useRgba_ && yuvBuffer_) {
                uint8_t* dstData[4] = { yuvBuffer_, yuvBuffer_ + (targetWidth * targetHeight), nullptr, nullptr };
                int dstLinesize[4] = { targetWidth, targetWidth, 0, 0 };

                sws_scale(swsCtx_, frame->data, frame->linesize, 0,
                    frame->height, dstData, dstLinesize);

                VideoFrame renderFrame{};
                memcpy(renderFrame.data, dstData, sizeof(dstData));
                memcpy(renderFrame.linesize, dstLinesize, sizeof(dstLinesize));
                renderFrame.width = targetWidth;
                renderFrame.height = targetHeight;
                renderFrame.pts = static_cast<int64_t>(pts * 1000000);
                renderFrame.format = AV_PIX_FMT_NV12;
                renderToWindow(renderFrame);
            }
        }

        delete (double*)frame->opaque;
        av_frame_free(&frame);
    }

    std::lock_guard<std::mutex> lock(videoMtx_);
    while (!videoFrameQueue_.empty()) {
        AVFrame* f = videoFrameQueue_.front();
        delete (double*)f->opaque;
        av_frame_free(&f);
        videoFrameQueue_.pop();
    }

    LOGI("Render loop ended");
}

bool FFmpegDecoder::renderToWindow(const VideoFrame& frame) {
    std::lock_guard<std::mutex> windowLock(windowMtx_);
    if (!ensureNativeWindowLocked(false)) return false;

    if (!nativeWindowConfigured_) {
        configureNativeWindowLocked();
        if (!nativeWindowConfigured_) {
            return false;
        }
    }

    OHNativeWindowBuffer* windowBuffer = nullptr;
    int ret = OH_NativeWindow_NativeWindowRequestBuffer(nativeWindow_, &windowBuffer, nullptr);

    if (ret != 0 || !windowBuffer) {
        consecutiveRequestFails_++;
        if (consecutiveRequestFails_ <= 5 || consecutiveRequestFails_ % 120 == 0) {
            LOGW("RequestBuffer failed: %{public}d (consecutive: %{public}d)",
                 ret, consecutiveRequestFails_);
        }
        if (consecutiveRequestFails_ == 1 || consecutiveRequestFails_ % 60 == 0) {
            nativeWindowConfigured_ = false;
            if (ensureNativeWindowLocked(true)) {
                configureNativeWindowLocked();
            }
        }
        return false;
    }

    consecutiveRequestFails_ = 0;

    BufferHandle* handle = OH_NativeWindow_GetBufferHandleFromNative(windowBuffer);
    if (!handle || !handle->virAddr) {
        Region emptyRegion = {nullptr, 0};
        OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, windowBuffer, -1, emptyRegion);
        nativeWindowConfigured_ = false;
        LOGW("Invalid native buffer handle");
        return false;
    }
    void* bufferAddr = handle->virAddr;

    const int stride = handle->stride > 0 ? handle->stride : frame.width;

    if (frame.format == AV_PIX_FMT_RGBA) {
        const int bytesPerPixel = 4;
        const int frameStride = frame.width * bytesPerPixel;
        const int bufferHeight = handle->height > 0 ? handle->height : frame.height;
        const int requiredSize = stride * bufferHeight * bytesPerPixel;

        if (handle->size < requiredSize) {
            LOGE("Buffer too small for RGBA: stride=%{public}d size=%{public}d needed=%{public}d",
                 stride, handle->size, requiredSize);
            Region emptyRegion = {nullptr, 0};
            OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, windowBuffer, -1, emptyRegion);
            nativeWindowConfigured_ = false;
            return false;
        }

        uint8_t* dst = (uint8_t*)bufferAddr;
        for (int i = 0; i < frame.height; i++) {
            memcpy(dst + i * stride * bytesPerPixel,
                   frame.data[0] + i * frame.linesize[0],
                   frameStride);
        }
    } else {
        const int bufferHeight = handle->height > 0 ? handle->height : frame.height;
        const int requiredSize = stride * bufferHeight * 3 / 2;

        if (stride < frame.width || bufferHeight < frame.height || handle->size < requiredSize) {
            LOGE("Buffer too small for NV12: stride=%{public}d height=%{public}d size=%{public}d",
                 stride, bufferHeight, handle->size);
            Region emptyRegion = {nullptr, 0};
            OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, windowBuffer, -1, emptyRegion);
            nativeWindowConfigured_ = false;
            return false;
        }

        uint8_t* dst = (uint8_t*)bufferAddr;
        uint8_t* dstY = dst;
        uint8_t* dstUV = dst + stride * bufferHeight;

        for (int i = 0; i < frame.height; i++) {
            memcpy(dstY + i * stride, frame.data[0] + i * frame.linesize[0], frame.width);
        }
        for (int i = 0; i < frame.height / 2; i++) {
            memcpy(dstUV + i * stride, frame.data[1] + i * frame.linesize[1], frame.width);
        }
    }

    Region region = {nullptr, 0};
    OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, windowBuffer, -1, region);

    if (!firstFrameRendered_.exchange(true)) {
        LOGI("First video frame rendered");
    }
    return true;
}
