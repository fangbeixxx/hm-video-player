#include "MediaUtils.h"
#include "decoder/FFmpegDecoder.h"
#include <hilog/log.h>

#undef LOG_TAG
#define LOG_TAG "MediaUtils"
static constexpr unsigned int LOG_DOMAIN = 0x0201;

double MediaUtils::getVideoDuration(const std::string& path) {
    AVFormatContext* ctx = nullptr;
    if (avformat_open_input(&ctx, path.c_str(), nullptr, nullptr) < 0) {
        return -1;
    }
    avformat_find_stream_info(ctx, nullptr);
    double duration = ctx->duration / (double)AV_TIME_BASE;
    avformat_close_input(&ctx);
    return duration;
}

bool MediaUtils::getVideoResolution(const std::string& path, int& width, int& height) {
    AVFormatContext* ctx = nullptr;
    if (avformat_open_input(&ctx, path.c_str(), nullptr, nullptr) < 0) {
        return false;
    }
    avformat_find_stream_info(ctx, nullptr);

    int idx = av_find_best_stream(ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (idx < 0) {
        avformat_close_input(&ctx);
        return false;
    }

    width = ctx->streams[idx]->codecpar->width;
    height = ctx->streams[idx]->codecpar->height;
    avformat_close_input(&ctx);
    return true;
}

bool MediaUtils::extractThumbnail(const std::string& path, double timeSec, const std::string& outPath) {
    // 简化实现：打开文件，seek 到指定时间，解码一帧，保存为图片
    // 实际项目中需要额外引入 libavformat 的图片输出支持
    LOGI("Extract thumbnail: %{public}s @ %{public}.1fs -> %{public}s",
         path.c_str(), timeSec, outPath.c_str());
    return false; // TODO: 实现缩略图提取
}

std::string MediaUtils::getCodecInfo(const std::string& path) {
    AVFormatContext* ctx = nullptr;
    if (avformat_open_input(&ctx, path.c_str(), nullptr, nullptr) < 0) {
        return "unknown";
    }
    avformat_find_stream_info(ctx, nullptr);

    std::string info;
    for (unsigned int i = 0; i < ctx->nb_streams; i++) {
        AVStream* stream = ctx->streams[i];
        const char* codecName = avcodec_get_name(stream->codecpar->codec_id);
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            info += "Video: " + std::string(codecName) +
                    " " + std::to_string(stream->codecpar->width) + "x" +
                    std::to_string(stream->codecpar->height);
        } else if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            info += " Audio: " + std::string(codecName) +
                    " " + std::to_string(stream->codecpar->sample_rate) + "Hz";
        }
    }

    avformat_close_input(&ctx);
    return info;
}
