/**
 * 播放器状态
 */
export enum PlayerState {
  IDLE = 'idle',
  INITIALIZED = 'initialized',
  PREPARING = 'preparing',
  PREPARED = 'prepared',
  PLAYING = 'playing',
  PAUSED = 'paused',
  STOPPED = 'stopped',
  COMPLETED = 'completed',
  ERROR = 'error'
}

/**
 * 播放速度
 */
export enum PlaybackSpeed {
  SPEED_0_5 = 0.5,
  SPEED_0_75 = 0.75,
  SPEED_1_0 = 1.0,
  SPEED_1_25 = 1.25,
  SPEED_1_5 = 1.5,
  SPEED_2_0 = 2.0
}

/**
 * 屏幕方向
 */
export enum ScreenOrientation {
  AUTO = 'auto',
  LANDSCAPE = 'landscape',
  PORTRAIT = 'portrait'
}

/**
 * 网络质量
 */
export enum NetworkQuality {
  EXCELLENT = 'excellent',
  GOOD = 'good',
  FAIR = 'fair',
  POOR = 'poor',
  OFFLINE = 'offline'
}

/**
 * 视频清晰度
 */
export enum VideoQuality {
  AUTO = 'auto',
  P360 = '360p',
  P480 = '480p',
  P720 = '720p',
  P1080 = '1080p',
  P4K = '4k'
}

/**
 * 排序方式
 */
export enum SortType {
  NAME = 'name',
  DATE_MODIFIED = 'date_modified',
  SIZE = 'size',
  DURATION = 'duration'
}

/**
 * 视频来源
 */
export enum VideoSource {
  LOCAL = 'local',
  NETWORK = 'network'
}

/**
 * 应用语言
 */
export enum AppLanguage {
  SYSTEM = 'system',
  ZH_CN = 'zh_CN',
  EN_US = 'en_US'
}
