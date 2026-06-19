#include <napi/native_api.h>
#include "decoder_napi.h"

/**
 * 模块注册 - 将 NAPI 函数导出到 ArkTS
 *
 * 使用方式 (ArkTS):
 *   import nativeModule from 'libharmonyos_video_player.so';
 *
 *   // 创建解码器
 *   const handle = nativeModule.createDecoder();
 *
 *   // 打开文件（支持 mkv, avi, flv 等）
 *   nativeModule.open(handle, '/data/storage/el2/base/videos/test.mkv');
 *
 *   // 设置渲染面
 *   nativeModule.setSurface(handle, surfaceId);
 *
 *   // 播放
 *   nativeModule.play(handle);
 *
 *   // 查询状态
 *   const time = nativeModule.getCurrentTime(handle);
 *   const duration = nativeModule.getDuration(handle);
 *   const codec = nativeModule.getVideoCodec(handle);
 *
 *   // 变速/音量
 *   nativeModule.setSpeed(handle, 1.5);
 *   nativeModule.setVolume(handle, 0.8);
 *
 *   // 跳转
 *   nativeModule.seek(handle, 60.0); // 跳转到 60 秒
 *
 *   // 销毁
 *   nativeModule.destroyDecoder(handle);
 *
 *   // 不创建实例即可查询媒体信息
 *   const info = nativeModule.getMediaInfo('/path/to/video.mkv');
 *   // => { duration: 120.5, width: 1920, height: 1080, codecInfo: "..." }
 */

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        // 生命周期
        {"createDecoder",   nullptr, CreateDecoder,   nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroyDecoder",  nullptr, DestroyDecoder,  nullptr, nullptr, nullptr, napi_default, nullptr},

        // 打开/关闭
        {"open",            nullptr, Open,            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"close",           nullptr, Close,           nullptr, nullptr, nullptr, napi_default, nullptr},

        // 播放控制
        {"play",            nullptr, Play,            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pause",           nullptr, Pause,           nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop",            nullptr, Stop,             nullptr, nullptr, nullptr, napi_default, nullptr},
        {"seek",            nullptr, Seek,            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSpeed",        nullptr, SetSpeed,        nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setVolume",       nullptr, SetVolume,       nullptr, nullptr, nullptr, napi_default, nullptr},

        // 状态查询
        {"isPlaying",       nullptr, IsPlaying,       nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getDuration",     nullptr, GetDuration,     nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getCurrentTime",  nullptr, GetCurrentTime,  nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getWidth",        nullptr, GetWidth,        nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getHeight",       nullptr, GetHeight,       nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVideoCodec",   nullptr, GetVideoCodec,   nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getAudioCodec",   nullptr, GetAudioCodec,   nullptr, nullptr, nullptr, napi_default, nullptr},

        // 渲染
        {"setSurface",      nullptr, SetSurface,      nullptr, nullptr, nullptr, napi_default, nullptr},

        // 工具
        {"getMediaInfo",    nullptr, GetMediaInfo,    nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isCodecSupported",nullptr, IsCodecSupported,nullptr, nullptr, nullptr, napi_default, nullptr},
    };

    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

// 模块定义
static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "harmonyos_video_player",
    .nm_priv = nullptr,
    .reserved = {0},
};

// 模块注册函数
extern "C" __attribute__((constructor))
void RegisterModule(void) {
    napi_module_register(&g_module);
}
