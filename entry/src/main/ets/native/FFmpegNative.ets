import nativeModule from 'libharmonyos-video-player.so';

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
  setSurfaceId(handle: number, surfaceId: string): boolean;
  setXComponentId(handle: number, xComponentId: string): boolean;
  registerXComponentSurface(xComponentId: string, context: Object): boolean;
  getMediaInfo(path: string): MediaInfo;
  isCodecSupported(codecName: string): boolean;
}

export interface MediaInfo {
  duration: number;
  width: number;
  height: number;
  codecInfo: string;
}

export class FFmpegDecoderInstance {
  private handle: number = -1;
  private native: NativeDecoderModule;

  constructor(native: NativeDecoderModule, handle: number) {
    this.native = native;
    this.handle = handle;
  }

  open(path: string): boolean {
    return this.native.open(this.handle, path);
  }

  close(): void {
    this.native.close(this.handle);
  }

  play(): void {
    this.native.play(this.handle);
  }

  pause(): void {
    this.native.pause(this.handle);
  }

  stop(): void {
    this.native.stop(this.handle);
  }

  seek(timeSec: number): void {
    this.native.seek(this.handle, timeSec);
  }

  setSpeed(speed: number): void {
    this.native.setSpeed(this.handle, speed);
  }

  setVolume(volume: number): void {
    this.native.setVolume(this.handle, volume);
  }

  isPlaying(): boolean {
    return this.native.isPlaying(this.handle);
  }

  getDuration(): number {
    return this.native.getDuration(this.handle);
  }

  getCurrentTime(): number {
    return this.native.getCurrentTime(this.handle);
  }

  getWidth(): number {
    return this.native.getWidth(this.handle);
  }

  getHeight(): number {
    return this.native.getHeight(this.handle);
  }

  getVideoCodec(): string {
    return this.native.getVideoCodec(this.handle);
  }

  getAudioCodec(): string {
    return this.native.getAudioCodec(this.handle);
  }

  setSurfaceId(surfaceId: string): boolean {
    return this.native.setSurfaceId(this.handle, surfaceId);
  }

  setXComponentId(xComponentId: string): boolean {
    return this.native.setXComponentId(this.handle, xComponentId);
  }

  destroy(): void {
    if (this.handle >= 0) {
      this.native.destroyDecoder(this.handle);
      this.handle = -1;
    }
  }
}

export class FFmpegNative {
  private static nativeModule: NativeDecoderModule = nativeModule as NativeDecoderModule;
  private static available: boolean = true;

  static init(): boolean {
    FFmpegNative.available = FFmpegNative.nativeModule.createDecoder !== undefined;
    return FFmpegNative.available;
  }

  static isAvailable(): boolean {
    return FFmpegNative.available;
  }

  static create(): FFmpegDecoderInstance | null {
    if (!FFmpegNative.init()) return null;

    const handle = FFmpegNative.nativeModule.createDecoder();
    if (handle < 0) return null;

    return new FFmpegDecoderInstance(FFmpegNative.nativeModule, handle);
  }

  static getMediaInfo(path: string): MediaInfo | null {
    if (!FFmpegNative.init()) return null;
    return FFmpegNative.nativeModule.getMediaInfo(path);
  }

  static registerXComponentSurface(xComponentId: string, context: Object): boolean {
    if (!FFmpegNative.init()) return false;
    return FFmpegNative.nativeModule.registerXComponentSurface(xComponentId, context);
  }

  static isCodecSupported(codecName: string): boolean {
    if (!FFmpegNative.init()) return false;
    return FFmpegNative.nativeModule.isCodecSupported(codecName);
  }
}
