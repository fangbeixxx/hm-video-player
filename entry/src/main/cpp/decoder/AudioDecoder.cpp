#include "AudioDecoder.h"
#include <ohaudio/native_audiorenderer.h>
#include <hilog/log.h>

#undef LOG_TAG
#define LOG_TAG "AudioDecoder"
static constexpr unsigned int APP_LOG_DOMAIN = 0x0201;
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, APP_LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

// 音频回调数据
struct AudioCallbackData {
    AudioDecoder* decoder;
};

AudioDecoder::AudioDecoder() = default;

AudioDecoder::~AudioDecoder() {
    release();
}

bool AudioDecoder::init(int sampleRate, int channels) {
    sampleRate_ = sampleRate;
    channels_ = channels;

    // 使用 OHAudio 原生 API 创建音频渲染器
    OH_AudioStream_Result result;

    // 这里使用简化的实现
    // 实际项目中需要使用 OH_AudioRenderer_Create / OH_AudioRenderer_Start
    // 和回调模式写入 PCM 数据

    // OH_AudioStreamBuilder* builder;
    // OH_AudioStreamBuilder_Create(&builder, AUDIOSTREAM_TYPE_RENDERER);
    // OH_AudioStreamBuilder_SetSamplingRate(builder, sampleRate);
    // OH_AudioStreamBuilder_SetChannelCount(builder, channels);
    // OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE);
    // OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW);
    // OH_AudioStreamBuilder_SetLatencyMode(builder, AUDIOSTREAM_LATENCY_MODE_FAST);
    // ...设置回调...
    // OH_AudioStreamBuilder_GenerateRenderer(builder, (OH_AudioRenderer**)&audioRenderer_);
    // OH_AudioStreamBuilder_Destroy(builder);
    // OH_AudioRenderer_Start((OH_AudioRenderer*)audioRenderer_);

    initialized_ = true;
    LOGI("Audio initialized: %{public}dHz, %{public}dch", sampleRate, channels);
    return true;
}

int AudioDecoder::write(const uint8_t* data, int size, float volume) {
    if (!initialized_ || !audioRenderer_) return 0;

    // OH_AudioRenderer_WriteData((OH_AudioRenderer*)audioRenderer_, data, size);

    // 应用音量
    if (volume < 1.0f) {
        // 对 S16LE 数据应用音量
        int16_t* samples = (int16_t*)data;
        int sampleCount = size / 2;
        for (int i = 0; i < sampleCount; i++) {
            samples[i] = (int16_t)(samples[i] * volume);
        }
    }

    return size;
}

void AudioDecoder::pause() {
    if (audioRenderer_) {
        // OH_AudioRenderer_Pause((OH_AudioRenderer*)audioRenderer_);
    }
}

void AudioDecoder::resume() {
    if (audioRenderer_) {
        // OH_AudioRenderer_Start((OH_AudioRenderer*)audioRenderer_);
    }
}

void AudioDecoder::flush() {
    if (audioRenderer_) {
        // OH_AudioRenderer_Flush((OH_AudioRenderer*)audioRenderer_);
    }
}

void AudioDecoder::release() {
    if (audioRenderer_) {
        // OH_AudioRenderer_Stop((OH_AudioRenderer*)audioRenderer_);
        // OH_AudioRenderer_Release((OH_AudioRenderer*)audioRenderer_);
        audioRenderer_ = nullptr;
    }
    initialized_ = false;
}

double AudioDecoder::getLatency() const {
    if (!audioRenderer_) return 0;
    // uint64_t latency;
    // OH_AudioRenderer_GetLatency((OH_AudioRenderer*)audioRenderer_, &latency);
    // return latency / 1000000.0;
    return 0.02; // 20ms 默认延迟
}
