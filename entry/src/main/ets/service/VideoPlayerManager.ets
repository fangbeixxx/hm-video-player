import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { FrameNode } from '@ohos.arkui.node';
import { PlayerState, PlaybackSpeed } from '../common/Enums';
import { Constants } from '../common/Constants';
import { FFmpegNative, FFmpegDecoderInstance } from '../native/FFmpegNative';
import { PlayerError, PlayerErrorCode, createPlayerError, mapFFmpegError } from '../common/PlayerError';

interface ErrorWithCode extends Error {
  code: number;
}

type DisplaySurface = string | FrameNode;

/**
 * 鎾斁鍣ㄤ簨浠跺洖璋冩帴鍙? */
export interface PlayerCallback {
  onStateChange?: (state: PlayerState) => void;
  onTimeUpdate?: (currentTime: number) => void;
  onDurationUpdate?: (duration: number) => void;
  onBufferingUpdate?: (isBuffering: boolean) => void;
  onError?: (error: PlayerError) => void;
  onCompleted?: () => void;
}

/**
 * 鎾斁寮曟搸绫诲瀷
 */
export enum PlaybackEngine {
  AUTO = 'auto',       // 鑷姩閫夋嫨锛氫紭鍏?AVPlayer锛屼笉鏀寔鏃跺垏鎹?FFmpeg
  AVPLAYER = 'avplayer',
  FFMPEG = 'ffmpeg'
}

/**
 * 瑙嗛鎾斁鍣ㄧ鐞嗙被
 * 鍙屽紩鎿庯細AVPlayer锛堢郴缁燂級+ FFmpeg锛堣蒋瑙ｇ爜锛? * AVPlayer 涓嶆敮鎸佹椂鑷姩鍥為€€鍒?FFmpeg
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
  private surfaceId: string = '';
  private xComponentId: string = '';
  private ffmpegSurface: DisplaySurface | null = null;
  private isPrepared: boolean = false;
  private abilityContext: common.UIAbilityContext | null = null;
  private suppressAVPlayerErrors: boolean = false;

  // ========== 鍏紑灞炴€?==========

  get state(): PlayerState { return this._state; }
  get currentTime(): number { return this._currentTime; }
  get duration(): number { return this._duration; }
  get isBuffering(): boolean { return this._isBuffering; }
  get speed(): PlaybackSpeed { return this._speed; }
  get volume(): number { return this._volume; }
  get isMuted(): boolean { return this._isMuted; }
  get isPlaying(): boolean { return this._state === PlayerState.PLAYING; }
  get engineType(): string { return this.useFFmpeg ? 'FFmpeg' : 'AVPlayer'; }

  setAbilityContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  // ========== 鐢熷懡鍛ㄦ湡 ==========

  /**
   * 鍒濆鍖栨挱鏀惧櫒
   * @param callback 浜嬩欢鍥炶皟
   * @param engine 寮曟搸鍋忓ソ
   */
  async init(callback?: PlayerCallback, engine?: PlaybackEngine): Promise<void> {
    await this.release();
    this.callback = callback || null;
    this.preferredEngine = engine || PlaybackEngine.AUTO;
    this._state = PlayerState.INITIALIZED;

    // 濡傛灉鎸囧畾 FFmpeg 鎴栬嚜鍔ㄦā寮忎笅棰勫姞杞?FFmpeg
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
   * 注意：无论 AVPlayer 处于什么状态（包括 error），都必须确保 avPlayer 被置 null，
   * 否则下次 init() → setupAVPlayerXxx() 会复用已损坏的 AVPlayer 实例。
   */
  async release(): Promise<void> {
    this.stopTimePoll();

    if (this.avPlayer) {
      try {
        this.removeAVPlayerListeners();
      } catch (e) {
        console.warn('[PlayerManager] removeAVPlayerListeners failed:', JSON.stringify(e));
      }
      try {
        await this.avPlayer.release();
      } catch (error) {
        const err = error as ErrorWithCode;
        console.warn('[PlayerManager] AVPlayer release failed, code:', err.code, 'msg:', err.message);
      }
      // 关键：不管 release() 是否抛异常，都必须置 null，防止复用已损坏的实例
      this.avPlayer = null;
    }

    if (this.ffmpegDecoder) {
      try {
        this.ffmpegDecoder.stop();
        this.ffmpegDecoder.destroy();
      } catch (e) {
        console.warn('[PlayerManager] FFmpeg release failed:', JSON.stringify(e));
      }
      this.ffmpegDecoder = null;
    }

    this.closeFd();
    this.useFFmpeg = false;
    this.isPrepared = false;
    this.appliedSurfaceId = '';
    this._state = PlayerState.IDLE;
    this._currentTime = 0;
    this._duration = 0;
    this._isBuffering = false;
  }

  setDisplaySurface(surface: DisplaySurface): void {
    if (typeof surface === 'string') {
      this.surfaceId = surface;
      this.ffmpegSurface = surface;
    } else {
      this.ffmpegSurface = surface;
    }

    if (this.useFFmpeg && this.ffmpegDecoder) {
      this.applyFFmpegSurface();
    }
  }

  setFFmpegXComponentId(xComponentId: string): void {
    this.xComponentId = xComponentId;
    if (this.useFFmpeg) {
      this.applyFFmpegSurface();
    }
  }

  private applyFFmpegSurface(): void {
    if (!this.ffmpegDecoder) {
      return;
    }

    if (this.xComponentId.length > 0) {
      const ready = this.ffmpegDecoder.setXComponentId(this.xComponentId);
      if (ready) {
        console.info('[PlayerManager] FFmpeg bound by native XComponent callback path');
      } else {
        console.warn('[PlayerManager] FFmpeg direct native window is not ready; skip legacy surfaceId fallback');
      }
      return;
    }

    console.warn('[PlayerManager] FFmpeg has no native XComponent id; skip legacy surfaceId fallback');
  }

  private appliedSurfaceId: string = '';

  private applyAVPlayerSurface(): void {
    if (!this.avPlayer) {
      return;
    }

    if (this.surfaceId.length > 0 && this.surfaceId !== this.appliedSurfaceId) {
      this.avPlayer.surfaceId = this.surfaceId;
      this.appliedSurfaceId = this.surfaceId;
      console.info('[PlayerManager] surfaceId set:', this.surfaceId);
    }
  }

  private applyAVPlayerDisplayOptions(): void {
    if (!this.avPlayer) {
      return;
    }

    try {
      this.avPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
      console.info('[PlayerManager] videoScaleType set: SCALED_ASPECT');
    } catch (error) {
      const err = error as ErrorWithCode;
      console.warn('[PlayerManager] skip videoScaleType, code:', err.code, 'msg:', err.message);
    }
  }

  private async disposeAVPlayer(): Promise<void> {
    if (!this.avPlayer) {
      return;
    }

    this.removeAVPlayerListeners();
    try {
      await this.avPlayer.release();
    } catch (error) {
      const err = error as ErrorWithCode;
      console.warn('[PlayerManager] AVPlayer release failed, code:', err.code, 'msg:', err.message);
    }
    this.avPlayer = null;
    this.isPrepared = false;
    this.closeFd();
  }

  private async waitForAVPlayerState(targetState: string, timeoutMs: number = 1500): Promise<void> {
    const start = Date.now();
    while (this.avPlayer && this.avPlayer.state !== targetState) {
      if (Date.now() - start > timeoutMs) {
        throw new Error(`Timed out waiting for AVPlayer state: ${targetState}, current=${this.avPlayer.state}`);
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 80));
    }
  }

  // ========== ????? ==========

  /**
   * ??????????????
   */
  async setSource(filePath: string): Promise<void> {
    console.info('[PlayerManager] setSource:', filePath);
    this.currentFilePath = filePath;

    try {
      if (this.shouldUseFFmpeg(filePath)) {
        console.info('[PlayerManager] using FFmpeg for:', filePath);
        await this.setupFFmpegSource(filePath);
        return;
      }

      this.suppressAVPlayerErrors = true;
      console.info('[PlayerManager] trying AVPlayer for:', filePath);
      await this.setupAVPlayerSource(filePath);
      console.info('[PlayerManager] AVPlayer setup success');
    } catch (e) {
      const err = e as ErrorWithCode;
      console.error('[PlayerManager] AVPlayer setup failed, code:', err.code, 'msg:', err.message);
      await this.disposeAVPlayer();
      if (this.isMediaLibraryUri(filePath)) {
        throw err;
      }
      console.warn('[PlayerManager] falling back to FFmpeg...');
      if (FFmpegNative.isAvailable()) {
        await this.setupFFmpegSource(filePath);
      } else {
        throw new Error('AVPlayer failed and FFmpeg is unavailable');
      }
    } finally {
      this.suppressAVPlayerErrors = false;
    }
  }

  /**
   * ??????URL?????
   */
  async setUrlSource(url: string): Promise<void> {
    this.currentFilePath = url;

    if (this.shouldUseFFmpeg(url)) {
      await this.setupFFmpegSource(url);
    } else {
      try {
        this.suppressAVPlayerErrors = true;
        await this.setupAVPlayerUrlSource(url);
      } catch (e) {
        await this.disposeAVPlayer();
        const err = e as ErrorWithCode;
        const errMsg: string = (typeof err.message === 'string') ? err.message : String(e);
        const code: string = (typeof err.code === 'number') ? String(err.code) : '?';
        console.warn('AVPlayer failed for URL, falling back to FFmpeg:', e);
        if (FFmpegNative.isAvailable()) {
          await this.setupFFmpegSource(url);
        } else {
          throw new Error('AVPlayer error [code=' + code + ']: ' + errMsg);
        }
      } finally {
        this.suppressAVPlayerErrors = false;
      }
    }
  }

  // ========== AVPlayer 瀹炵幇 ==========

  private async setupAVPlayerSource(filePath: string): Promise<void> {
    console.info('[PlayerManager] setupAVPlayerSource:', filePath);
    // If AVPlayer exists but is in error state, destroy and recreate it.
    // A stale errored AVPlayer cannot be reused — it must be replaced.
    if (this.avPlayer && this.avPlayer.state === 'error') {
      console.warn('[PlayerManager] AVPlayer in error state, disposing and recreating...');
      await this.disposeAVPlayer();
    }
    if (!this.avPlayer) {
      console.info('[PlayerManager] creating AVPlayer...');
      this.avPlayer = await media.createAVPlayer();
      this.setupAVPlayerListeners();
      console.info('[PlayerManager] AVPlayer created');
    }

    this.closeFd();
    this.isPrepared = false;
    console.info('[PlayerManager] opening file...');
    const fd = this.isMediaLibraryUri(filePath)
      ? await this.openMediaLibraryFd(filePath)
      : fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY).fd;
    this.openedFd = fd;
    console.info('[PlayerManager] file opened, fd:', fd);
    // Step 1: Set fdSrc → AVPlayer state transitions from idle → initialized
    this.avPlayer.fdSrc = { fd: fd, offset: 0, length: 0 };
    console.info('[PlayerManager] fdSrc set');
    await this.waitForAVPlayerState('initialized');
    // Step 2: SurfaceId can ONLY be set when AVPlayer is in 'initialized' state
    this.applyAVPlayerSurface();
    // Step 3: Prepare → state transitions from initialized → prepared
    await this.avPlayer.prepare();
    await this.waitForAVPlayerState('prepared');
    this.applyAVPlayerDisplayOptions();
    this.isPrepared = true;
    console.info('[PlayerManager] AVPlayer prepared');
    this.useFFmpeg = false;
  }

  private async setupAVPlayerUrlSource(url: string): Promise<void> {
    // If AVPlayer exists but is in error state, destroy and recreate it.
    // A stale errored AVPlayer cannot be reused — it must be replaced.
    if (this.avPlayer && this.avPlayer.state === 'error') {
      console.warn('[PlayerManager] AVPlayer in error state, disposing and recreating...');
      await this.disposeAVPlayer();
    }
    if (!this.avPlayer) {
      this.avPlayer = await media.createAVPlayer();
      this.setupAVPlayerListeners();
    }

    this.closeFd();
    this.isPrepared = false;
    // Step 1: Set URL → AVPlayer state transitions from idle → initialized
    this.avPlayer.url = url;
    await this.waitForAVPlayerState('initialized');
    // Step 2: SurfaceId can ONLY be set when AVPlayer is in 'initialized' state
    this.applyAVPlayerSurface();
    // Step 3: Prepare → state transitions from initialized → prepared
    await this.avPlayer.prepare();
    // Network streams (HLS/DASH) can take several seconds to resolve — use longer timeout.
    const isHttpStream: boolean = url.startsWith('http://') || url.startsWith('https://');
    await this.waitForAVPlayerState('prepared', isHttpStream ? 15000 : 5000);
    this.applyAVPlayerDisplayOptions();
    this.isPrepared = true;
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
      this._isBuffering = type === media.BufferingInfoType.BUFFERING_START;
      this.callback?.onBufferingUpdate?.(this._isBuffering);
    });

    this.avPlayer.on('error', (err) => {
      console.error(`[PlayerManager] AVPlayer error!`);
      console.error(`[PlayerManager] AVPlayer error code: ${err.code}`);
      console.error(`[PlayerManager] AVPlayer error message: ${err.message}`);
      console.error(`[PlayerManager] AVPlayer error - currentFilePath: ${this.currentFilePath}`);
      console.error(`[PlayerManager] AVPlayer error - state: ${this._state}`);
      if (this.suppressAVPlayerErrors) {
        console.warn('[PlayerManager] AVPlayer error suppressed during source probing');
        return;
      }
      this._state = PlayerState.ERROR;
      this.isPrepared = false;
      // Map AVPlayer errors into the shared PlayerErrorCode space.
      const errorCode = this.mapAVPlayerErrorCode(err.code, err.message);
      const playerError = createPlayerError(errorCode,
        `AVPlayer error [code=${err.code}]: ${err.message}\nFile: ${this.currentFilePath}`);
      this.callback?.onError?.(playerError);
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

  // ========== FFmpeg 瀹炵幇 ==========

  private async setupFFmpegSource(path: string): Promise<void> {
    if (!this.ffmpegDecoder) {
      this.ffmpegDecoder = FFmpegNative.create();
      if (!this.ffmpegDecoder) {
        throw new Error('FFmpeg native module not available');
      }
    }

    this.useFFmpeg = true;
    this.isPrepared = false;
    this.applyFFmpegSurface();
    const success = this.ffmpegDecoder.open(path);
    if (!success) {
      throw new Error('FFmpeg failed to open: ' + path);
    }

    this._duration = this.ffmpegDecoder.getDuration() * 1000; // 杞绉?    this._state = PlayerState.PREPARED;
    this.isPrepared = true;
    this.callback?.onStateChange?.(PlayerState.PREPARED);
    this.callback?.onDurationUpdate?.(this._duration);
  }

  /**
   * 鍚姩 FFmpeg 鏃堕棿杞
   */
  private startTimePoll(): void {
    this.stopTimePoll();
    this.currentTimePollId = setInterval(() => {
      if (this.ffmpegDecoder && this.useFFmpeg) {
        const timeSec = this.ffmpegDecoder.getCurrentTime();
        this._currentTime = timeSec * 1000;
        this.callback?.onTimeUpdate?.(this._currentTime);
      }
    }, 200);
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
    } else if (this.avPlayer) {
      if (!this.isPrepared && this.avPlayer.state === 'initialized') {
        await this.avPlayer.prepare();
        await this.waitForAVPlayerState('prepared');
        this.isPrepared = true;
      }
      await this.avPlayer.play();
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
    this.isPrepared = false;
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
      this.ffmpegDecoder.seek(clampedTime / 1000);
    } else if (this.avPlayer !== null) {
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
      this.avPlayer.setSpeed(this.toMediaPlaybackSpeed(speed));
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
   * 璁剧疆娓叉煋琛ㄩ潰锛團Fmpeg 妯″紡涓嬮渶瑕侊級
   */
  setSurface(surface: DisplaySurface): void {
    this.setDisplaySurface(surface);
  }

  /**
   * ???????? FFmpeg
   */
  /**
   * 判断是否应使用 FFmpeg 解码（AUTO 模式下检测格式）
   */
  private shouldUseFFmpeg(path: string): boolean {
    if (this.preferredEngine === PlaybackEngine.FFMPEG) return true;
    if (this.preferredEngine === PlaybackEngine.AVPLAYER) return false;
    if (this.isMediaLibraryUri(path)) return false;

    // AUTO mode: use FFmpeg for formats AVPlayer may not handle well
    const lowerPath = path.toLowerCase();
    const ffmpegFormats: string[] = [
      '.mkv', '.avi', '.wmv', '.flv', '.rmvb', '.rm',
      '.vob', '.m2ts', '.ogv', '.asf', '.divx', '.xvid',
      '.f4v', '.mts', '.m2t'
    ];
    for (const format of ffmpegFormats) {
      if (lowerPath.endsWith(format)) {
        console.info('[PlayerManager] AUTO mode: using FFmpeg for format ' + format);
        return true;
      }
    }
    return false;
  }

  private isMediaLibraryUri(path: string): boolean {
    return path.startsWith('file://media/');
  }

  private async openMediaLibraryFd(uri: string): Promise<number> {
    if (!this.abilityContext) {
      throw new Error('Media library context is not ready');
    }
    const helper = photoAccessHelper.getPhotoAccessHelper(this.abilityContext);
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI.toString(), uri);

    const fetchResult = await helper.getAssets({
      fetchColumns: [photoAccessHelper.PhotoKeys.URI.toString()],
      predicates: predicates
    });

    try {
      const assets = await fetchResult.getAllObjects();
      if (assets.length === 0) {
        throw new Error(`Media asset not found for uri: ${uri}`);
      }
      const fd = await assets[0].getReadOnlyFd();
      console.info('[PlayerManager] media library fd opened:', fd);
      return fd;
    } finally {
      fetchResult.close();
    }
  }

  private closeFd(): void {
    if (this.openedFd >= 0) {
      try { fileIo.closeSync(this.openedFd); } catch (e) { /* ignore */ }
      this.openedFd = -1;
    }
  }

  private mapState(state: string): PlayerState {
    switch (state) {
      case 'idle':
        return PlayerState.IDLE;
      case 'initialized':
        return PlayerState.INITIALIZED;
      case 'preparing':
        return PlayerState.PREPARING;
      case 'prepared':
        return PlayerState.PREPARED;
      case 'playing':
        return PlayerState.PLAYING;
      case 'paused':
        return PlayerState.PAUSED;
      case 'stopped':
        return PlayerState.STOPPED;
      case 'completed':
        return PlayerState.COMPLETED;
      case 'error':
        return PlayerState.ERROR;
      case 'released':
        return PlayerState.IDLE;
      default:
        return PlayerState.IDLE;
    }
  }

  private toMediaPlaybackSpeed(speed: PlaybackSpeed): media.PlaybackSpeed {
    switch (speed) {
      case PlaybackSpeed.SPEED_0_5:
        return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
      case PlaybackSpeed.SPEED_0_75:
        return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
      case PlaybackSpeed.SPEED_1_25:
        return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
      case PlaybackSpeed.SPEED_1_5:
        return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
      case PlaybackSpeed.SPEED_2_0:
        return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
      default:
        return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    }
  }

  /**
   * 灏?AVPlayer 閿欒鐮佹槧灏勫埌缁熶竴鐨?PlayerErrorCode
   */
  private mapAVPlayerErrorCode(avCode: number, avMsg: string): PlayerErrorCode {
    // AVPlayer 甯歌閿欒鐮?    // 5400101: 鏂囦欢涓嶅瓨鍦ㄦ垨鏃犳硶鎵撳紑
    // 5400102: 涓嶆敮鎸佺殑鏍煎紡
    // 5400103: 瑙ｇ爜閿欒
    // 5400104: 缃戠粶閿欒
    // 5400105: 鏈煡閿欒
    const msg = avMsg.toLowerCase();

    switch (avCode) {
      case 13900001:
      case 201:
        return PlayerErrorCode.PERMISSION_DENIED;
      case 5400101:
        if (msg.includes('permission') || msg.includes('鏉冮檺')) {
          return PlayerErrorCode.PERMISSION_DENIED;
        }
        if (msg.includes('not found')) {
          return PlayerErrorCode.FILE_NOT_FOUND;
        }
        return PlayerErrorCode.FILE_READ_ERROR;

      case 5400102:
        if (msg.includes('surfaceid') || msg.includes('surface')) {
          return PlayerErrorCode.RENDERER_SURFACE_ERROR;
        }
        if (msg.includes('not permit') || msg.includes('not allowed') || msg.includes('state')) {
          return PlayerErrorCode.FILE_READ_ERROR;
        }
        if (msg.includes('codec')) {
          return PlayerErrorCode.DECODER_NOT_FOUND;
        }
        if (msg.includes('format') || msg.includes('鏍煎紡')) {
          return PlayerErrorCode.FILE_FORMAT_UNKNOWN;
        }
        return PlayerErrorCode.UNSUPPORTED_CODEC;

      case 5400103:
        return PlayerErrorCode.DECODE_ERROR;

      case 5400104:
        if (msg.includes('timeout') || msg.includes('瓒呮椂')) {
          return PlayerErrorCode.NETWORK_TIMEOUT;
        }
        if (msg.includes('dns') || msg.includes('鍩熷悕')) {
          return PlayerErrorCode.NETWORK_DNS_ERROR;
        }
        return PlayerErrorCode.NETWORK_UNAVAILABLE;

      default:
        // Fallback to message heuristics when the numeric code is unknown.
        if (msg.includes('codec') || msg.includes('format')) {
          return PlayerErrorCode.UNSUPPORTED_CODEC;
        }
        if (msg.includes('network') || msg.includes('http')) {
          return PlayerErrorCode.NETWORK_UNAVAILABLE;
        }
        if (msg.includes('surface') || msg.includes('render')) {
          return PlayerErrorCode.RENDERER_SURFACE_ERROR;
        }
        return PlayerErrorCode.UNKNOWN;
    }
  }
}






