#ifndef LOG_UTILS_H
#define LOG_UTILS_H

#include <hilog/log.h>

static constexpr unsigned int APP_LOG_DOMAIN = 0x0201;

#define LOGI(tag, fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, APP_LOG_DOMAIN, tag, fmt, ##__VA_ARGS__)
#define LOGW(tag, fmt, ...) OH_LOG_Print(LOG_APP, LOG_WARN, APP_LOG_DOMAIN, tag, fmt, ##__VA_ARGS__)
#define LOGE(tag, fmt, ...) OH_LOG_Print(LOG_APP, LOG_ERROR, APP_LOG_DOMAIN, tag, fmt, ##__VA_ARGS__)

#endif // LOG_UTILS_H
