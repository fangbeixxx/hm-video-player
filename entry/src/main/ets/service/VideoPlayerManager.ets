import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { PlayerState, PlaybackSpeed } from '../common/Enums';
import { Constants } from '../common/Constants';
import { FFmpegNative, FFmpegDecoderInstance } from '../native/FFmpegNative';

/**
 * 播放器事件回调接口
 */
export interface PlayerCallback {
  onStateChange?: (state: PlayerState) => void;
  onTimeUpdate?: (currentTime: number) => void;
  onDurationUpdate?: (duration: number) => void;
  onBufferingUpdate?: (isBuffering: boolean) => void;
  onError?: (errorCode: number, errorMsg: string) => void;
  onCompleted?: () => void;
}

/**
 * 播放引擎类型
 */
export enum PlaybackEngine {
  AUTO = 'auto',       // 自动选择：优先 AVPlayer，不支持时切换 FFmpeg
  AVPLAYER = 'avplayer',
  FFMPEG = 'ffmpeg'
}

/**
 * 视频播放器管理类
 * 双引擎：AVPlayer（系统）+ FFmpeg（软解码）
 * AVPlayer 不支持时自动回退到 FFmpeg
 */
export class VideoPlayerManager {
  // AVPlayer
  private avPlayer: media.AVPlayer | null = null;
  // FFmpeg
  private ffmpegDecoder: FFmpegDecoderInstance | null = null;
  private useFFmpeg: boolean = false;

  private callback: PlayerCallback | null = null;
  private _state: PlayerState = PlayerState.IDLE;
  private _currentTime: number = 0;
  private _duration: number = 0;
  private _isBuffering: boolean = false;
  private _speed: PlaybackSpeed = PlaybackSpeed.SPEED_1_0;
  private _volume: number = 1.0;
  private _isMuted: boolean = false;
  private openedFd: number = -1;
  private preferredEngine: PlaybackEngine = PlaybackEngine.AUTO;
  private currentFilePath: string = '';
  private currentTimePollId: number = -1;

  // ========== 公开属性 ==========

  get state(): PlayerState { return this._state; }
  get currentTime(): number { return this._currentTime; }
  get duration(): number { return this._duration; }
  get isBuffering(): boolean { return this._isBuffering; }
  get speed(): PlaybackSpeed { return this._speed; }
  get volume(): number { return this._volume; }
  get isMuted(): boolean { return this._isMuted; }
  get isPlaying(): boolean { return this._state === PlayerState.PLAYING; }
  get engineType(): string { return this.useFFmpeg ? 'FFmpeg' : 'AVPlayer'; }

  // ========== 生命周期 ==========

  /**
   * 初始化播放器
   * @param callback 事件回调
   * @param engine 引擎偏好
   */
  async init(callback?: PlayerCallback, engine?: PlaybackEngine): Promise<void> {
    await this.release();
    this.callback = callback || null;
    this.preferredEngine = engine || PlaybackEngine.AUTO;
    this._state = PlayerState.INITIALIZED;

    // 如果指定 FFmpeg 或自动模式下预加载 FFmpeg
    if (this.preferredEngine === PlaybackEngine.FFMPEG) {
      this.ffmpegDecoder = FFmpegNative.create();
      if (!this.ffmpegDecoder) {
        throw new Error('FFmpeg native module not available');
      }
      this.useFFmpeg = true;
    }
  }

  /**
   * 释放播放器资源
   */
  async release(): Promise<void> {
    this.stopTimePoll();

    if (this.avPlayer) {
      this.removeAVPlayerListeners();
      await this.avPlayer.release();
      this.avPlayer = null;
    }

    if (this.ffmpegDecoder) {
      this.ffmpegDecoder.stop();
      this.ffmpegDecoder.destroy();
      this.ffmpegDecoder = null;
    }

    this.closeFd();
    this.useFFmpeg = false;
    this._state = PlayerState.IDLE;
    this._currentTime = 0;
    this._duration = 0;
    this._isBuffering = false;
  }

  // ========== 播放源设置 ==========

  /**
   * 设置本地文件播放源
   */
  async setSource(filePath: string): Promise<void> {
    this.currentFilePath = filePath;

    // 判断是否需要 FFmpeg
    if (this.shouldUseFFmpeg(filePath)) {
      await this.setupFFmpegSource(filePath);
    } else {
      try {
        await this.setupAVPlayerSource(filePath);
      } catch (e) {
        // AVPlayer 失败时回退到 FFmpeg
        console.warn('AVPlayer failed, falling back to FFmpeg:', e);
        if (FFmpegNative.isAvailable()) {
          await this.setupFFmpegSource(filePath);
        } else {
          throw e;
        }
      }
    }
  }

  /**
   * 设置网络URL播放源
   */
  async setUrlSource(url: string): Promise<void> {
    this.currentFilePath = url;

    if (this.shouldUseFFmpeg(url)) {
      await this.setupFFmpegSource(url);
    } else {
      try {
        await this.setupAVPlayerUrlSource(url);
      } catch (e) {
        console.warn('AVPlayer failed for URL, falling back to FFmpeg:', e);
        if (FFmpegNative.isAvailable()) {
          await this.setupFFmpegSource(url);
        } else {
          throw e;
        }
      }
    }
  }

  // ========== AVPlayer 实现 ==========

  private async setupAVPlayerSource(filePath: string): Promise<void> {
    if (!this.avPlayer) {
      this.avPlayer = await media.createAVPlayer();
      this.setupAVPlayerListeners();
    }

    this.closeFd();
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    this.openedFd = file.fd;
    this.avPlayer.fdSrc = { fd: file.fd, offset: 0, length: 0 };
    this.useFFmpeg = false;
  }

  private async setupAVPlayerUrlSource(url: string): Promise<void> {
    if (!this.avPlayer) {
      this.avPlayer = await media.createAVPlayer();
      this.setupAVPlayerListeners();
    }

    this.closeFd();
    this.avPlayer.url = url;
    this.useFFmpeg = false;
  }

  private setupAVPlayerListeners(): void {
    if (!this.avPlayer) return;

    this.avPlayer.on('stateChange', (state: string) => {
      const mapped = this.mapState(state);
      this._state = mapped;
      this.callback?.onStateChange?.(mapped);
      if (mapped === PlayerState.COMPLETED) {
        this.callback?.onCompleted?.();
      }
    });

    this.avPlayer.on('timeUpdate', (timeMs: number) => {
      this._currentTime = timeMs;
      this.callback?.onTimeUpdate?.(timeMs);
    });

    this.avPlayer.on('durationUpdate', (duration: number) => {
      this._duration = duration;
      this.callback?.onDurationUpdate?.(duration);
    });

    this.avPlayer.on('bufferingUpdate', (type: media.BufferingInfoType) => {
      this._isBuffering = (type === media.BufferingInfoType.BUFFERING_START ||
        type === media.BufferingInfoType.BUFFERING_LOADING);
      this.callback?.onBufferingUpdate?.(this._isBuffering);
    });

    this.avPlayer.on('error', (err) => {
      console.error(`AVPlayer error: ${err.code} - ${err.message}`);
      this._state = PlayerState.ERROR;
      this.callback?.onError?.(err.code, err.message);
    });
  }

  private removeAVPlayerListeners(): void {
    if (!this.avPlayer) return;
    this.avPlayer.off('stateChange');
    this.avPlayer.off('timeUpdate');
    this.avPlayer.off('durationUpdate');
    this.avPlayer.off('bufferingUpdate');
    this.avPlayer.off('error');
  }

  // ========== FFmpeg 实现 ==========

  private async setupFFmpegSource(path: string): Promise<void> {
    if (!this.ffmpegDecoder) {
      this.ffmpegDecoder = FFmpegNative.create();
      if (!this.ffmpegDecoder) {
        throw new Error('FFmpeg native module not available');
      }
    }

    this.useFFmpeg = true;
    const success = this.ffmpegDecoder.open(path);
    if (!success) {
      throw new Error('FFmpeg failed to open: ' + path);
    }

    this._duration = this.ffmpegDecoder.getDuration() * 1000; // 转毫秒
    this._state = PlayerState.PREPARED;
    this.callback?.onStateChange?.(PlayerState.PREPARED);
    this.callback?.onDurationUpdate?.(this._duration);
  }

  /**
   * 启动 FFmpeg 时间轮询
   */
  private startTimePoll(): void {
    this.stopTimePoll();
    this.currentTimePollId = setInterval(() => {
      if (this.ffmpegDecoder && this.useFFmpeg) {
        const timeSec = this.ffmpegDecoder.getCurrentTime();
        this._currentTime = timeSec * 1000;
        this.callback?.onTimeUpdate?.(this._currentTime);
      }
    }, 200) as unknown as number;
  }

  private stopTimePoll(): void {
    if (this.currentTimePollId >= 0) {
      clearInterval(this.currentTimePollId);
      this.currentTimePollId = -1;
    }
  }

  // ========== 播放控制 ==========

  async play(): Promise<void> {
    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.ffmpegDecoder.play();
      this._state = PlayerState.PLAYING;
      this.callback?.onStateChange?.(PlayerState.PLAYING);
      this.startTimePoll();
    } else {
      await this.avPlayer?.play();
    }
  }

  async pause(): Promise<void> {
    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.ffmpegDecoder.pause();
      this._state = PlayerState.PAUSED;
      this.callback?.onStateChange?.(PlayerState.PAUSED);
    } else {
      await this.avPlayer?.pause();
    }
  }

  async stop(): Promise<void> {
    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.ffmpegDecoder.stop();
      this.stopTimePoll();
    } else {
      await this.avPlayer?.stop();
    }
  }

  async togglePlayPause(): Promise<void> {
    if (this.isPlaying) {
      await this.pause();
    } else {
      await this.play();
    }
  }

  async seekTo(timeMs: number): Promise<void> {
    const clampedTime = Math.max(0, Math.min(timeMs, this._duration));
    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.ffmpegDecoder.seek(clampedTime / 1000); // 毫秒 -> 秒
    } else if (this.avPlayer) {
      this.avPlayer.seek(clampedTime);
    }
  }

  async seekForward(stepMs: number = Constants.DEFAULT_SEEK_STEP): Promise<void> {
    await this.seekTo(this._currentTime + stepMs);
  }

  async seekBackward(stepMs: number = Constants.DEFAULT_SEEK_STEP): Promise<void> {
    await this.seekTo(this._currentTime - stepMs);
  }

  async setSpeed(speed: PlaybackSpeed): Promise<void> {
    this._speed = speed;
    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.ffmpegDecoder.setSpeed(speed);
    } else if (this.avPlayer) {
      this.avPlayer.setSpeed(speed as media.PlaybackSpeed);
    }
  }

  async cycleSpeed(): Promise<void> {
    const speeds = [
      PlaybackSpeed.SPEED_0_5,
      PlaybackSpeed.SPEED_0_75,
      PlaybackSpeed.SPEED_1_0,
      PlaybackSpeed.SPEED_1_25,
      PlaybackSpeed.SPEED_1_5,
      PlaybackSpeed.SPEED_2_0
    ];
    const currentIdx = speeds.indexOf(this._speed);
    const nextIdx = (currentIdx + 1) % speeds.length;
    await this.setSpeed(speeds[nextIdx]);
  }

  async setVolume(vol: number): Promise<void> {
    this._volume = Math.max(0, Math.min(1, vol));
    const effectiveVolume = this._isMuted ? 0 : this._volume;
    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.ffmpegDecoder.setVolume(effectiveVolume);
    } else if (this.avPlayer) {
      this.avPlayer.setVolume(effectiveVolume);
    }
  }

  async toggleMute(): Promise<void> {
    this._isMuted = !this._isMuted;
    await this.setVolume(this._volume);
  }

  async volumeUp(step: number = Constants.DEFAULT_VOLUME_STEP): Promise<void> {
    await this.setVolume(this._volume + step);
  }

  async volumeDown(step: number = Constants.DEFAULT_VOLUME_STEP): Promise<void> {
    await this.setVolume(this._volume - step);
  }

  /**
   * 设置渲染表面（FFmpeg 模式下需要）
   */
  setSurface(surfaceId: string): void {
    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.ffmpegDecoder.setSurface(surfaceId);
    }
  }

  /**
   * 获取视频编码信息
   */
  getCodecInfo(): string {
    if (this.useFFmpeg && this.ffmpegDecoder) {
      const vCodec = this.ffmpegDecoder.getVideoCodec();
      const aCodec = this.ffmpegDecoder.getAudioCodec();
      return `V: ${vCodec}, A: ${aCodec}`;
    }
    return 'System AVPlayer';
  }

  // ========== 辅助方法 ==========

  /**
   * 判断是否应该使用 FFmpeg
   * 检查文件扩展名，对于 AVPlayer 可能不支持的格式优先使用 FFmpeg
   */
  private shouldUseFFmpeg(path: string): boolean {
    if (this.preferredEngine === PlaybackEngine.FFMPEG) return true;
    if (this.preferredEngine === PlaybackEngine.AVPLAYER) return false;

    // 自动模式：对 AVPlayer 不擅长的格式使用 FFmpeg
    const ffmpegFormats = [
      '.mkv', '.avi', '.flv', '.wmv', '.webm', '.ts',
      '.mpg', '.mpeg', '.vob', '.m2ts', '.rmvb', '.rm',
      '.3gp', '.asf', '.ogv'
    ];

    const lowerPath = path.toLowerCase();
    return ffmpegFormats.some(ext => lowerPath.endsWith(ext));
  }

  private closeFd(): void {
    if (this.openedFd >= 0) {
      try { fileIo.closeSync(this.openedFd); } catch (e) { /* ignore */ }
      this.openedFd = -1;
    }
  }

  private mapState(state: string): PlayerState {
    const stateMap: Record<string, PlayerState> = {
      'idle': PlayerState.IDLE,
      'initialized': PlayerState.INITIALIZED,
      'preparing': PlayerState.PREPARING,
      'prepared': PlayerState.PREPARED,
      'playing': PlayerState.PLAYING,
      'paused': PlayerState.PAUSED,
      'stopped': PlayerState.STOPPED,
      'completed': PlayerState.COMPLETED,
      'error': PlayerState.ERROR,
      'released': PlayerState.IDLE
    };
    return stateMap[state] || PlayerState.IDLE;
  }
}
