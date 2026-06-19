#pragma once

#include <napi/native_api.h>
#include "decoder/FFmpegDecoder.h"
#include <memory>
#include <unordered_map>

/**
 * NAPI 桥接层 - 将 FFmpegDecoder 暴露给 ArkTS
 *
 * ArkTS 调用方式:
 *   import nativeModule from 'libharmonyos-video-player.so';
 *   const decoder = nativeModule.createDecoder();
 *   nativeModule.open(decoder, '/path/to/video.mkv');
 *   nativeModule.play(decoder);
 */

// 全局解码器实例管理
static std::unordered_map<int64_t, std::shared_ptr<FFmpegDecoder>> g_decoders;
static int64_t g_nextHandle = 1;

// ========== 创建/销毁 ==========

/**
 * 创建解码器实例
 * @return decoderHandle (number)
 */
napi_value CreateDecoder(napi_env env, napi_callback_info info);

/**
 * 销毁解码器实例
 * @param handle decoderHandle
 */
napi_value DestroyDecoder(napi_env env, napi_callback_info info);

// ========== 打开/关闭 ==========

/**
 * 打开媒体文件
 * @param handle decoderHandle
 * @param path 文件路径
 * @return boolean 是否成功
 */
napi_value Open(napi_env env, napi_callback_info info);

/**
 * 关闭解码器
 * @param handle decoderHandle
 */
napi_value Close(napi_env env, napi_callback_info info);

// ========== 播放控制 ==========

napi_value Play(napi_env env, napi_callback_info info);
napi_value Pause(napi_env env, napi_callback_info info);
napi_value Stop(napi_env env, napi_callback_info info);
napi_value Seek(napi_env env, napi_callback_info info);
napi_value SetSpeed(napi_env env, napi_callback_info info);
napi_value SetVolume(napi_env env, napi_callback_info info);

// ========== 状态查询 ==========

napi_value IsPlaying(napi_env env, napi_callback_info info);
napi_value GetDuration(napi_env env, napi_callback_info info);
napi_value GetCurrentTime(napi_env env, napi_callback_info info);
napi_value GetWidth(napi_env env, napi_callback_info info);
napi_value GetHeight(napi_env env, napi_callback_info info);
napi_value GetVideoCodec(napi_env env, napi_callback_info info);
napi_value GetAudioCodec(napi_env env, napi_callback_info info);

// ========== 渲染 ==========

/**
 * 设置渲染窗口（从 ArkTS Video 组件获取 surfaceId）
 * @param handle decoderHandle
 * @param surfaceId string
 */
napi_value SetSurface(napi_env env, napi_callback_info info);

// ========== 工具函数 ==========

/**
 * 获取视频信息（不创建解码器实例，用于扫描阶段）
 * @param path 文件路径
 * @return { duration, width, height, videoCodec, audioCodec }
 */
napi_value GetMediaInfo(napi_env env, napi_callback_info info);

/**
 * 检查是否支持某个编码格式
 * @param codecName 编码名称
 * @return boolean
 */
napi_value IsCodecSupported(napi_env env, napi_callback_info info);

// 辅助：从 napi 获取 handle
std::shared_ptr<FFmpegDecoder> GetDecoder(napi_env env, napi_callback_info info);
