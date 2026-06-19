#pragma once

#include <cstdint>

/**
 * 音频解码器 - 与系统音频输出对接
 */
class AudioDecoder {
public:
    AudioDecoder();
    ~AudioDecoder();

    /**
     * 初始化音频输出
     * @param sampleRate 采样率
     * @param channels 声道数
     */
    bool init(int sampleRate, int channels);

    /**
     * 写入 PCM 数据并播放
     * @param data PCM 数据（S16LE 格式）
     * @param size 数据大小（字节）
     * @param volume 音量 0.0~1.0
     * @return 实际写入的字节数
     */
    int write(const uint8_t* data, int size, float volume = 1.0f);

    /**
     * 暂停
     */
    void pause();

    /**
     * 恢复
     */
    void resume();

    /**
     * 清空缓冲区
     */
    void flush();

    /**
     * 释放资源
     */
    void release();

    /**
     * 获取当前播放延迟（秒）
     */
    double getLatency() const;

private:
    void* audioRenderer_ = nullptr;  // OH_AudioRenderer*
    int sampleRate_ = 0;
    int channels_ = 0;
    bool initialized_ = false;
};
