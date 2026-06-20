#include "decoder_napi.h"
#include "decoder/FFmpegDecoder.h"
#include "utils/MediaUtils.h"
#include <arkui/native_node_napi.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <cerrno>
#include <cstdlib>
#include <hilog/log.h>
#include <native_window/external_window.h>

#undef LOG_TAG
#define LOG_TAG "DecoderNapi"
static constexpr unsigned int APP_LOG_DOMAIN = 0x0201;
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, APP_LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

namespace {

struct BoundSurfaceHolder {
    ArkUI_NodeHandle node = nullptr;
    OH_ArkUI_SurfaceHolder* holder = nullptr;
    OH_ArkUI_SurfaceCallback* callback = nullptr;
    std::weak_ptr<FFmpegDecoder> decoder;
};

std::unordered_map<int64_t, std::shared_ptr<BoundSurfaceHolder>> g_surfaceHolders;
std::unordered_map<std::string, int64_t> g_xComponentHandleById;
std::unordered_map<std::string, OHNativeWindow*> g_xComponentWindowById;
OH_NativeXComponent_Callback g_nativeXComponentCallbacks {};
bool g_nativeXComponentCallbacksReady = false;

void ReleaseBoundSurfaceHolder(int64_t handle) {
    auto it = g_surfaceHolders.find(handle);
    if (it == g_surfaceHolders.end()) {
        return;
    }

    auto binding = it->second;
    if (binding->holder && binding->callback) {
        OH_ArkUI_SurfaceHolder_RemoveSurfaceCallback(binding->holder, binding->callback);
    }
    if (binding->callback) {
        OH_ArkUI_SurfaceCallback_Dispose(binding->callback);
    }
    if (binding->holder) {
        OH_ArkUI_SurfaceHolder_Dispose(binding->holder);
    }
    g_surfaceHolders.erase(it);

    for (auto iter = g_xComponentHandleById.begin(); iter != g_xComponentHandleById.end();) {
        if (iter->second == handle) {
            iter = g_xComponentHandleById.erase(iter);
        } else {
            ++iter;
        }
    }
}

std::shared_ptr<FFmpegDecoder> FindDecoderByXComponent(OH_NativeXComponent* component) {
    if (component == nullptr) {
        return nullptr;
    }

    char id[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    uint64_t size = sizeof(id);
    if (OH_NativeXComponent_GetXComponentId(component, id, &size) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        LOGE("FindDecoderByXComponent failed: get id failed");
        return nullptr;
    }

    auto itHandle = g_xComponentHandleById.find(id);
    if (itHandle == g_xComponentHandleById.end()) {
        LOGE("FindDecoderByXComponent failed: no decoder bound for id=%{public}s", id);
        return nullptr;
    }

    auto itDecoder = g_decoders.find(itHandle->second);
    if (itDecoder == g_decoders.end()) {
        LOGE("FindDecoderByXComponent failed: decoder handle missing for id=%{public}s", id);
        return nullptr;
    }

    return itDecoder->second;
}

std::string GetXComponentId(OH_NativeXComponent* component) {
    if (component == nullptr) {
        return "";
    }

    char id[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    uint64_t size = sizeof(id);
    if (OH_NativeXComponent_GetXComponentId(component, id, &size) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        LOGE("GetXComponentId failed");
        return "";
    }

    return std::string(id);
}

void OnNativeXComponentSurfaceCreated(OH_NativeXComponent* component, void* window) {
    std::string id = GetXComponentId(component);
    if (!id.empty()) {
        g_xComponentWindowById[id] = static_cast<OHNativeWindow*>(window);
    }

    auto decoder = FindDecoderByXComponent(component);
    if (!decoder) {
        if (!id.empty()) {
            LOGI("OnNativeXComponentSurfaceCreated cached window for id=%{public}s", id.c_str());
        }
        return;
    }

    auto* nativeWindow = static_cast<OHNativeWindow*>(window);
    decoder->setNativeWindow(nativeWindow);
    LOGI("OnNativeXComponentSurfaceCreated bound native window");
}

void OnNativeXComponentSurfaceChanged(OH_NativeXComponent* component, void* window) {
    std::string id = GetXComponentId(component);
    if (!id.empty()) {
        g_xComponentWindowById[id] = static_cast<OHNativeWindow*>(window);
    }

    auto decoder = FindDecoderByXComponent(component);
    if (!decoder) {
        if (!id.empty()) {
            LOGI("OnNativeXComponentSurfaceChanged cached window for id=%{public}s", id.c_str());
        }
        return;
    }

    auto* nativeWindow = static_cast<OHNativeWindow*>(window);
    decoder->setNativeWindow(nativeWindow);
    LOGI("OnNativeXComponentSurfaceChanged refreshed native window");
}

void OnNativeXComponentSurfaceDestroyed(OH_NativeXComponent* component, void* window) {
    std::string id = GetXComponentId(component);
    if (!id.empty()) {
        g_xComponentWindowById.erase(id);
    }

    auto decoder = FindDecoderByXComponent(component);
    if (!decoder) {
        return;
    }

    decoder->setNativeWindow(nullptr);
    LOGI("OnNativeXComponentSurfaceDestroyed cleared native window");
}


void OnNativeXComponentSurfaceShow(OH_NativeXComponent* component, void* window) {
    OnNativeXComponentSurfaceCreated(component, window);
    LOGI("OnNativeXComponentSurfaceShow forwarded to surface-created handler");
}

void OnNativeXComponentSurfaceHide(OH_NativeXComponent* component, void* window) {
    OnNativeXComponentSurfaceDestroyed(component, window);
    LOGI("OnNativeXComponentSurfaceHide forwarded to surface-destroyed handler");
}
void EnsureNativeXComponentCallbacks() {
    if (g_nativeXComponentCallbacksReady) {
        return;
    }

    g_nativeXComponentCallbacks.OnSurfaceCreated = OnNativeXComponentSurfaceCreated;
    g_nativeXComponentCallbacks.OnSurfaceChanged = OnNativeXComponentSurfaceChanged;
    g_nativeXComponentCallbacks.OnSurfaceDestroyed = OnNativeXComponentSurfaceDestroyed;
    g_nativeXComponentCallbacks.DispatchTouchEvent = nullptr;
    g_nativeXComponentCallbacksReady = true;
}

void OnArkUISurfaceCreated(OH_ArkUI_SurfaceHolder* surfaceHolder) {
    if (surfaceHolder == nullptr) {
        return;
    }

    auto* userData = static_cast<BoundSurfaceHolder*>(OH_ArkUI_SurfaceHolder_GetUserData(surfaceHolder));
    if (userData == nullptr) {
        return;
    }

    auto decoder = userData->decoder.lock();
    if (!decoder) {
        return;
    }

    OHNativeWindow* nativeWindow = OH_ArkUI_XComponent_GetNativeWindow(surfaceHolder);
    if (nativeWindow == nullptr) {
        LOGE("OnArkUISurfaceCreated failed: native window is null");
        return;
    }

    decoder->setNativeWindow(nativeWindow);
    LOGI("OnArkUISurfaceCreated bound native window");
}

void OnArkUISurfaceChanged(OH_ArkUI_SurfaceHolder* surfaceHolder, uint64_t width, uint64_t height) {
    auto* userData = static_cast<BoundSurfaceHolder*>(OH_ArkUI_SurfaceHolder_GetUserData(surfaceHolder));
    if (userData == nullptr) {
        return;
    }

    auto decoder = userData->decoder.lock();
    if (!decoder) {
        return;
    }

    OHNativeWindow* nativeWindow = OH_ArkUI_XComponent_GetNativeWindow(surfaceHolder);
    if (nativeWindow == nullptr) {
        LOGE("OnArkUISurfaceChanged failed: native window is null");
        return;
    }

    decoder->setNativeWindow(nativeWindow);
    LOGI("OnArkUISurfaceChanged size=%{public}llu x %{public}llu",
         static_cast<unsigned long long>(width), static_cast<unsigned long long>(height));
}

void OnArkUISurfaceDestroyed(OH_ArkUI_SurfaceHolder* surfaceHolder) {
    auto* userData = static_cast<BoundSurfaceHolder*>(OH_ArkUI_SurfaceHolder_GetUserData(surfaceHolder));
    if (userData == nullptr) {
        return;
    }

    auto decoder = userData->decoder.lock();
    if (!decoder) {
        return;
    }

    decoder->setNativeWindow(nullptr);
    LOGI("OnArkUISurfaceDestroyed cleared native window");
}

}

// ========== 杈呭姪鍑芥暟 ==========

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

// ========== 瀹炵幇 ==========

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
        // Remove decoder from the map.
        size_t argc = 1;
        napi_value args[1];
        napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
        int64_t handle = 0;
        napi_get_value_int64(env, args[0], &handle);
        ReleaseBoundSurfaceHolder(handle);
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
    if (it == g_decoders.end()) return nullptr;

    // Bridge decoder callbacks back to ArkTS polling/update flow.
    DecoderCallbacks callbacks;
    callbacks.onPrepared = [env, handle](int w, int h, double dur) {
        LOGI("Prepared: %dx%d, %.2fs", w, h, dur);
    };
    callbacks.onProgress = [env, handle](double time) {
        // 鍥炶皟鍒?JS 闇€瑕佷娇鐢?napi_threadsafe_function
        // 杩欓噷绠€鍖栧鐞嗭紝鐢?ArkTS 渚у畾鏃惰疆璇?getCurrentTime
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
    if (!decoder) return CreateBool(env, false);

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
    if (!decoder) return CreateBool(env, false);

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
    if (!decoder) return CreateBool(env, false);

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

napi_value SetSurfaceId(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t handle = 0;
    napi_get_value_int64(env, args[0], &handle);

    auto it = g_decoders.find(handle);
    if (it == g_decoders.end()) return nullptr;
    auto decoder = it->second;
    if (!decoder) return CreateBool(env, false);

    char surfaceId[256];
    size_t surfaceIdLen = 0;
    napi_get_value_string_utf8(env, args[1], surfaceId, sizeof(surfaceId), &surfaceIdLen);

    if (surfaceIdLen == 0) {
        LOGE("SetSurfaceId failed: empty surfaceId");
        return nullptr;
    }

    errno = 0;
    char* endPtr = nullptr;
    unsigned long long parsedSurfaceId = std::strtoull(surfaceId, &endPtr, 10);
    if (errno != 0 || endPtr == surfaceId || *endPtr != '\0') {
        LOGE("SetSurfaceId failed: invalid surfaceId %{public}s", surfaceId);
        return nullptr;
    }

    ReleaseBoundSurfaceHolder(handle);
    decoder->setSurfaceId(static_cast<uint64_t>(parsedSurfaceId));
    LOGI("SetSurfaceId cached by surfaceId: %{public}s", surfaceId);
    return nullptr;
}

napi_value SetXComponentId(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t handle = 0;
    napi_get_value_int64(env, args[0], &handle);

    auto it = g_decoders.find(handle);
    if (it == g_decoders.end()) return nullptr;
    auto decoder = it->second;
    if (!decoder) return CreateBool(env, false);

    char xComponentId[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    size_t xComponentIdLen = 0;
    napi_get_value_string_utf8(env, args[1], xComponentId, sizeof(xComponentId), &xComponentIdLen);
    if (xComponentIdLen == 0) {
        LOGE("SetXComponentId failed: empty xComponentId");
        return nullptr;
    }

    EnsureNativeXComponentCallbacks();
    g_xComponentHandleById[xComponentId] = handle;
    ReleaseBoundSurfaceHolder(handle);
    decoder->setNativeWindow(nullptr);
    auto itWindow = g_xComponentWindowById.find(xComponentId);
    if (itWindow != g_xComponentWindowById.end() && itWindow->second != nullptr) {
        decoder->setNativeWindow(itWindow->second);
        LOGI("SetXComponentId bound cached native window for id=%{public}s", xComponentId);
        return nullptr;
    }
    LOGI("SetXComponentId cached xComponentId=%{public}s; waiting for native XComponent callback binding", xComponentId);
    return nullptr;
}

napi_value RegisterXComponentSurface(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char xComponentId[OH_XCOMPONENT_ID_LEN_MAX + 1] = {};
    size_t xComponentIdLen = 0;
    napi_get_value_string_utf8(env, args[0], xComponentId, sizeof(xComponentId), &xComponentIdLen);
    if (xComponentIdLen == 0) {
        LOGE("RegisterXComponentSurface failed: empty xComponentId");
        return nullptr;
    }

    napi_value nativeObjValue = nullptr;
    napi_status status = napi_get_named_property(env, args[1], OH_NATIVE_XCOMPONENT_OBJ, &nativeObjValue);
    if (status != napi_ok || nativeObjValue == nullptr) {
        LOGE("RegisterXComponentSurface failed: native xcomponent object missing for id=%{public}s", xComponentId);
        return nullptr;
    }

    OH_NativeXComponent* nativeXComponent = nullptr;
    status = napi_unwrap(env, nativeObjValue, reinterpret_cast<void**>(&nativeXComponent));
    if (status != napi_ok || nativeXComponent == nullptr) {
        LOGE("RegisterXComponentSurface failed: unwrap native xcomponent failed for id=%{public}s", xComponentId);
        return nullptr;
    }

    EnsureNativeXComponentCallbacks();
    int32_t ret = OH_NativeXComponent_RegisterCallback(nativeXComponent, &g_nativeXComponentCallbacks);
    if (ret != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        LOGE("RegisterXComponentSurface failed: register callback ret=%{public}d id=%{public}s", ret, xComponentId);
        return nullptr;
    }

    LOGI("RegisterXComponentSurface registered native callback for id=%{public}s", xComponentId);
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










