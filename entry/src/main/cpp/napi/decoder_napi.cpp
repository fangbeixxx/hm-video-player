#include "decoder_napi.h"
#include "decoder/FFmpegDecoder.h"
#include "utils/MediaUtils.h"
#include <hilog/log.h>
#include <native_window/external_window.h>

#undef LOG_TAG
#define LOG_TAG "DecoderNapi"
static constexpr unsigned int LOG_DOMAIN = 0x0201;

// ========== 辅助函数 ==========

std::shared_ptr<FFmpegDecoder> GetDecoder(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t handle = 0;
    napi_get_value_int64(env, args[0], &handle);

    auto it = g_decoders.find(handle);
    if (it == g_decoders.end()) return nullptr;
    return it->second;
}

static napi_value CreateInt64(napi_env env, int64_t val) {
    napi_value result;
    napi_create_int64(env, val, &result);
    return result;
}

static napi_value CreateDouble(napi_env env, double val) {
    napi_value result;
    napi_create_double(env, val, &result);
    return result;
}

static napi_value CreateBool(napi_env env, bool val) {
    napi_value result;
    napi_get_boolean(env, val, &result);
    return result;
}

static napi_value CreateString(napi_env env, const std::string& str) {
    napi_value result;
    napi_create_string_utf8(env, str.c_str(), str.length(), &result);
    return result;
}

// ========== 实现 ==========

napi_value CreateDecoder(napi_env env, napi_callback_info) {
    auto decoder = std::make_shared<FFmpegDecoder>();
    int64_t handle = g_nextHandle++;
    g_decoders[handle] = decoder;

    LOGI("Created decoder, handle: %{public}lld", (long long)handle);
    return CreateInt64(env, handle);
}

napi_value DestroyDecoder(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    if (decoder) {
        decoder->close();
        // 从 map 中移除
        size_t argc = 1;
        napi_value args[1];
        napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
        int64_t handle = 0;
        napi_get_value_int64(env, args[0], &handle);
        g_decoders.erase(handle);
        LOGI("Destroyed decoder, handle: %{public}lld", (long long)handle);
    }
    return nullptr;
}

napi_value Open(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t handle = 0;
    napi_get_value_int64(env, args[0], &handle);

    char pathBuf[4096];
    size_t pathLen = 0;
    napi_get_value_string_utf8(env, args[1], pathBuf, sizeof(pathBuf), &pathLen);

    auto it = g_decoders.find(handle);
    if (it == g_decoders.end()) return CreateBool(env, false);

    // 设置回调（通过 napi_threadsafe_function 桥接到 JS 线程）
    DecoderCallbacks callbacks;
    callbacks.onPrepared = [env, handle](int w, int h, double dur) {
        LOGI("Prepared: %dx%d, %.2fs", w, h, dur);
    };
    callbacks.onProgress = [env, handle](double time) {
        // 回调到 JS 需要使用 napi_threadsafe_function
        // 这里简化处理，由 ArkTS 侧定时轮询 getCurrentTime
    };
    callbacks.onCompleted = [env, handle]() {
        LOGI("Playback completed");
    };
    callbacks.onError = [env, handle](const std::string& err) {
        LOGE("Error: %{public}s", err.c_str());
    };

    it->second->setCallbacks(callbacks);
    bool success = it->second->open(std::string(pathBuf, pathLen));

    LOGI("Open %{public}s -> %{public}s", pathBuf, success ? "OK" : "FAIL");
    return CreateBool(env, success);
}

napi_value Close(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    if (decoder) decoder->close();
    return nullptr;
}

napi_value Play(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    if (decoder) decoder->play();
    return nullptr;
}

napi_value Pause(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    if (decoder) decoder->pause();
    return nullptr;
}

napi_value Stop(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    if (decoder) decoder->stop();
    return nullptr;
}

napi_value Seek(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto decoder = GetDecoder(env, info);
    if (!decoder) return nullptr;

    double timeSec = 0;
    napi_get_value_double(env, args[1], &timeSec);
    decoder->seek(timeSec);
    return nullptr;
}

napi_value SetSpeed(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto decoder = GetDecoder(env, info);
    if (!decoder) return nullptr;

    double speed = 1.0;
    napi_get_value_double(env, args[1], &speed);
    decoder->setSpeed(speed);
    return nullptr;
}

napi_value SetVolume(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto decoder = GetDecoder(env, info);
    if (!decoder) return nullptr;

    double vol = 1.0;
    napi_get_value_double(env, args[1], &vol);
    decoder->setVolume(vol);
    return nullptr;
}

napi_value IsPlaying(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    return CreateBool(env, decoder ? decoder->isPlaying() : false);
}

napi_value GetDuration(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    return CreateDouble(env, decoder ? decoder->getDuration() : 0);
}

napi_value GetCurrentTime(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    return CreateDouble(env, decoder ? decoder->getCurrentTime() : 0);
}

napi_value GetWidth(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    napi_value result;
    napi_create_int32(env, decoder ? decoder->getWidth() : 0, &result);
    return result;
}

napi_value GetHeight(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    napi_value result;
    napi_create_int32(env, decoder ? decoder->getHeight() : 0, &result);
    return result;
}

napi_value GetVideoCodec(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    return CreateString(env, decoder ? decoder->getVideoCodecName() : "none");
}

napi_value GetAudioCodec(napi_env env, napi_callback_info info) {
    auto decoder = GetDecoder(env, info);
    return CreateString(env, decoder ? decoder->getAudioCodecName() : "none");
}

napi_value SetSurface(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto decoder = GetDecoder(env, info);
    if (!decoder) return nullptr;

    // 从 surfaceId 获取 NativeWindow
    char surfaceId[256];
    size_t surfaceIdLen = 0;
    napi_get_value_string_utf8(env, args[1], surfaceId, sizeof(surfaceId), &surfaceIdLen);

    OHNativeWindow* window = nullptr;
    // OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &window);
    // decoder->setWindow(window);

    LOGI("SetSurface: %{public}s", surfaceId);
    return nullptr;
}

napi_value GetMediaInfo(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char pathBuf[4096];
    size_t pathLen = 0;
    napi_get_value_string_utf8(env, args[0], pathBuf, sizeof(pathBuf), &pathLen);

    std::string path(pathBuf, pathLen);
    int width = 0, height = 0;
    double duration = MediaUtils::getVideoDuration(path);
    MediaUtils::getVideoResolution(path, width, height);
    std::string codecInfo = MediaUtils::getCodecInfo(path);

    napi_value result;
    napi_create_object(env, &result);

    napi_value val;
    napi_create_double(env, duration, &val);
    napi_set_named_property(env, result, "duration", val);

    napi_create_int32(env, width, &val);
    napi_set_named_property(env, result, "width", val);

    napi_create_int32(env, height, &val);
    napi_set_named_property(env, result, "height", val);

    val = CreateString(env, codecInfo);
    napi_set_named_property(env, result, "codecInfo", val);

    return result;
}

napi_value IsCodecSupported(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char codecName[128];
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], codecName, sizeof(codecName), &len);

    const AVCodec* codec = avcodec_find_decoder_by_name(codecName);
    return CreateBool(env, codec != nullptr);
}
