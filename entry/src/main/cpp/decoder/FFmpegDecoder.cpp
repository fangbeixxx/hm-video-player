#include "FFmpegDecoder.h"
#include <cstring>
#include <algorithm>

// HarmonyOS HiLog
static constexpr unsigned int LOG_DOMAIN = 0x0201;
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGW(...) OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

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

    videoStreamIdx_ = -1;
    audioStreamIdx_ = -1;
    videoClock_ = 0;
    audioClock_ = 0;
    masterClock_ = 0;
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
                     codec->name, audioCodecCtx_->channels, audioCodecCtx_->sample_rate);
            }
        }
    }

    // 初始化 SWS（像素格式转换）
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
        yuvBufferSize_ = av_image_get_buffer_size(AV_PIX_FMT_NV12,
            videoCodecCtx_->width, videoCodecCtx_->height, 1);
        yuvBuffer_ = (uint8_t*)av_malloc(yuvBufferSize_);
    }

    // 初始化 SWR（音频重采样）
    if (audioCodecCtx_) {
        swrCtx_ = swr_alloc();
        av_opt_set_int(swrCtx_, "in_channel_layout", audioCodecCtx_->channel_layout, 0);
        av_opt_set_int(swrCtx_, "in_sample_rate", audioCodecCtx_->sample_rate, 0);
        av_opt_set_sample_fmt(swrCtx_, "in_sample_fmt", audioCodecCtx_->sample_fmt, 0);
        av_opt_set_int(swrCtx_, "out_channel_layout", audioCodecCtx_->channel_layout, 0);
        av_opt_set_int(swrCtx_, "out_sample_rate", audioCodecCtx_->sample_rate, 0);
        av_opt_set_sample_fmt(swrCtx_, "out_sample_fmt", AV_SAMPLE_FMT_S16, 0);

        if (swr_init(swrCtx_) < 0) {
            LOGE("Failed to init SWR context");
            swr_free(&swrCtx_);
            swrCtx_ = nullptr;
        }
    }

    return true;
}

// ========== 播放控制 ==========

void FFmpegDecoder::play() {
    if (running_ && playing_) return;

    running_ = true;
    playing_ = true;
    paused_ = false;

    if (!videoThread_.joinable() && videoCodecCtx_) {
        videoThread_ = std::thread(&FFmpegDecoder::videoDecodeLoop, this);
        renderThread_ = std::thread(&FFmpegDecoder::renderLoop, this);
    }
    if (!audioThread_.joinable() && audioCodecCtx_) {
        audioThread_ = std::thread(&FFmpegDecoder::audioDecodeLoop, this);
    }

    startTime_ = av_gettime() / 1000000.0;
    LOGI("Playback started");
}

void FFmpegDecoder::pause() {
    paused_ = true;
    LOGI("Playback paused");
}

void FFmpegDecoder::stop() {
    running_ = false;
    playing_ = false;
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

void FFmpegDecoder::setWindow(OHNativeWindow* window) {
    nativeWindow_ = window;
    if (window && videoCodecCtx_) {
        // 设置窗口缓冲区大小
        OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY,
            videoCodecCtx_->width, videoCodecCtx_->height);
    }
}

// ========== 状态查询 ==========

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
        AVFrame* cloned = av_frame_clone();
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
                audioFrame.channels = audioCodecCtx_->channels;

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
    int bytesPerSample = 2 * srcFrame->channels; // S16 format
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

        // 通知进度
        if (callbacks_.onProgress) {
            callbacks_.onProgress(pts);
        }

        // 同步：等待到正确的显示时间
        double delay = pts - (av_gettime() / 1000000.0 - startTime_);
        if (delay > 0.005) {
            // 根据速度调整延迟
            delay /= speed_.load();
            std::this_thread::sleep_for(
                std::chrono::microseconds((int64_t)(delay * 1000000)));
        }

        // 转换像素格式
        if (swsCtx_ && yuvBuffer_) {
            uint8_t* dstData[4] = { yuvBuffer_, yuvBuffer_ + yuvBufferSize_ * 2 / 3, nullptr, nullptr };
            int dstLinesize[4] = { videoCodecCtx_->width, videoCodecCtx_->width, 0, 0 };

            sws_scale(swsCtx_, frame->data, frame->linesize, 0,
                frame->height, dstData, dstLinesize);

            // 渲染到 NativeWindow
            if (nativeWindow_) {
                renderToWindow({dstData, dstLinesize,
                    frame->width, frame->height, (int64_t)(pts * 1000000), AV_PIX_FMT_NV12});
            }

            // 通知视频帧（用于 UI 回调）
            if (callbacks_.onVideoFrame) {
                VideoFrame vf;
                memcpy(vf.data, dstData, sizeof(dstData));
                memcpy(vf.linesize, dstLinesize, sizeof(dstLinesize));
                vf.width = frame->width;
                vf.height = frame->height;
                vf.pts = (int64_t)(pts * 1000000);
                vf.format = AV_PIX_FMT_NV12;
                callbacks_.onVideoFrame(vf);
            }
        }

        delete (double*)frame->opaque;
        av_frame_free(&frame);
    }

    // 清空剩余帧
    std::lock_guard<std::mutex> lock(videoMtx_);
    while (!videoFrameQueue_.empty()) {
        AVFrame* f = videoFrameQueue_.front();
        delete (double*)f->opaque;
        av_frame_free(&f);
        videoFrameQueue_.pop();
    }

    LOGI("Render loop ended");
}

void FFmpegDecoder::renderToWindow(const VideoFrame& frame) {
    if (!nativeWindow_) return;

    OHNativeWindowBuffer* windowBuffer = nullptr;
    int ret = OH_NativeWindow_NativeWindowRequestBuffer(nativeWindow_, &windowBuffer, nullptr);
    if (ret != 0) return;

    // 获取缓冲区信息
    void* bufferAddr = nullptr;
    OH_NativeWindow_GetBufferAddrFromNative(windowBuffer, &bufferAddr);
    if (!bufferAddr) {
        OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, windowBuffer, -1, nullptr);
        return;
    }

    int bufferWidth, bufferHeight;
    OH_NativeWindow_NativeWindowHandleOpt(nativeWindow_, GET_BUFFER_GEOMETRY,
        &bufferWidth, &bufferHeight);

    // NV12 数据拷贝
    uint8_t* dst = (uint8_t*)bufferAddr;
    int ySize = frame.width * frame.height;
    int uvSize = frame.width * frame.height / 2;

    // Y 平面
    for (int i = 0; i < frame.height; i++) {
        memcpy(dst + i * frame.width, frame.data[0] + i * frame.linesize[0], frame.width);
    }
    // UV 平面
    for (int i = 0; i < frame.height / 2; i++) {
        memcpy(dst + ySize + i * frame.width,
            frame.data[1] + i * frame.linesize[1], frame.width);
    }

    Region region = {nullptr, 0};
    OH_NativeWindow_NativeWindowFlushBuffer(nativeWindow_, windowBuffer, -1, &region);
}
