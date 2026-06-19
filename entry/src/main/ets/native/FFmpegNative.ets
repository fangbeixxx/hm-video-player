/**
 * FFmpeg 原生模块 ArkTS 封装
 *
 * 通过 NAPI 调用 C++ FFmpeg 解码器
 * 支持 MKV、AVI、FLV、VP9、AC3、DTS 等系统解码器不支持的格式
 *
 * 用法:
 *   import { FFmpegNative } from '../native/FFmpegNative';
 *   const decoder = FFmpegNative.create();
 *   decoder.open('/path/to/video.mkv');
 *   decoder.play();
 */

// 原生模块类型声明
interface NativeDecoderModule {
  createDecoder(): number;
  destroyDecoder(handle: number): void;
  open(handle: number, path: string): boolean;
  close(handle: number): void;
  play(handle: number): void;
  pause(handle: number): void;
  stop(handle: number): void;
  seek(handle: number, timeSec: number): void;
  setSpeed(handle: number, speed: number): void;
  setVolume(handle: number, volume: number): void;
  isPlaying(handle: number): boolean;
  getDuration(handle: number): number;
  getCurrentTime(handle: number): number;
  getWidth(handle: number): number;
  getHeight(handle: number): number;
  getVideoCodec(handle: number): string;
  getAudioCodec(handle: number): string;
  setSurface(handle: number, surfaceId: string): void;
  getMediaInfo(path: string): MediaInfo;
  isCodecSupported(codecName: string): boolean;
}

export interface MediaInfo {
  duration: number;
  width: number;
  height: number;
  codecInfo: string;
}

/**
 * FFmpeg 解码器实例
 */
export class FFmpegDecoderInstance {
  private handle: number = -1;
  private native: NativeDecoderModule;

  constructor(native: NativeDecoderModule, handle: number) {
    this.native = native;
    this.handle = handle;
  }

  /**
   * 打开媒体文件
   */
  open(path: string): boolean {
    return this.native.open(this.handle, path);
  }

  /**
   * 关闭
   */
  close(): void {
    this.native.close(this.handle);
  }

  /**
   * 播放
   */
  play(): void {
    this.native.play(this.handle);
  }

  /**
   * 暂停
   */
  pause(): void {
    this.native.pause(this.handle);
  }

  /**
   * 停止
   */
  stop(): void {
    this.native.stop(this.handle);
  }

  /**
   * 跳转（秒）
   */
  seek(timeSec: number): void {
    this.native.seek(this.handle, timeSec);
  }

  /**
   * 设置播放速度
   */
  setSpeed(speed: number): void {
    this.native.setSpeed(this.handle, speed);
  }

  /**
   * 设置音量 0.0~1.0
   */
  setVolume(volume: number): void {
    this.native.setVolume(this.handle, volume);
  }

  /**
   * 是否正在播放
   */
  isPlaying(): boolean {
    return this.native.isPlaying(this.handle);
  }

  /**
   * 获取时长（秒）
   */
  getDuration(): number {
    return this.native.getDuration(this.handle);
  }

  /**
   * 获取当前播放时间（秒）
   */
  getCurrentTime(): number {
    return this.native.getCurrentTime(this.handle);
  }

  /**
   * 获取视频宽度
   */
  getWidth(): number {
    return this.native.getWidth(this.handle);
  }

  /**
   * 获取视频高度
   */
  getHeight(): number {
    return this.native.getHeight(this.handle);
  }

  /**
   * 获取视频编码名称
   */
  getVideoCodec(): string {
    return this.native.getVideoCodec(this.handle);
  }

  /**
   * 获取音频编码名称
   */
  getAudioCodec(): string {
    return this.native.getAudioCodec(this.handle);
  }

  /**
   * 设置渲染表面
   */
  setSurface(surfaceId: string): void {
    this.native.setSurface(this.handle, surfaceId);
  }

  /**
   * 释放解码器
   */
  destroy(): void {
    if (this.handle >= 0) {
      this.native.destroyDecoder(this.handle);
      this.handle = -1;
    }
  }
}

/**
 * FFmpeg 原生模块管理类
 */
export class FFmpegNative {
  private static nativeModule: NativeDecoderModule | null = null;
  private static available: boolean = false;

  /**
   * 初始化（自动加载原生库）
   */
  static init(): boolean {
    if (this.nativeModule) return this.available;

    try {
      // 加载 NAPI 共享库
      // @ts-ignore - 动态导入原生库
      this.nativeModule = globalThis.__NATIVE_MODULE__ ||
        requireNapi('harmonyos_video_player') as NativeDecoderModule;
      this.available = true;
      console.info('FFmpeg native module loaded');
    } catch (e) {
      console.warn('FFmpeg native module not available, falling back to AVPlayer');
      this.available = false;
    }

    return this.available;
  }

  /**
   * 是否可用（FFmpeg 库是否加载成功）
   */
  static isAvailable(): boolean {
    return this.available;
  }

  /**
   * 创建解码器实例
   */
  static create(): FFmpegDecoderInstance | null {
    if (!this.init() || !this.nativeModule) return null;

    const handle = this.nativeModule.createDecoder();
    if (handle < 0) return null;

    return new FFmpegDecoderInstance(this.nativeModule, handle);
  }

  /**
   * 获取媒体信息（不创建实例）
   */
  static getMediaInfo(path: string): MediaInfo | null {
    if (!this.init() || !this.nativeModule) return null;
    return this.nativeModule.getMediaInfo(path);
  }

  /**
   * 检查编码格式是否支持
   */
  static isCodecSupported(codecName: string): boolean {
    if (!this.init() || !this.nativeModule) return false;
    return this.nativeModule.isCodecSupported(codecName);
  }
}
