import { fileIo } from '@kit.CoreFileKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import picker from '@ohos.file.picker';
import util from '@ohos.util';
import {
  IjkMediaPlayer,
  OnBufferingUpdateListener,
  OnCompletionListener,
  OnErrorListener,
  OnInfoListener,
  OnPreparedListener,
  OnSeekCompleteListener,
  OnTimedTextListener,
  OnVideoSizeChangedListener,
  VideoCodecMode
} from '@ohos/ijkplayer';
import { VideoPlayerManager, PlaybackEngine } from '../service/VideoPlayerManager';
import { ControlPanel } from './ControlPanel';
import { ErrorToast } from './ErrorDialog';
import { DanmakuLayer } from './DanmakuLayer';
import { PlayerState, PlaybackSpeed, AppLanguage } from '../common/Enums';
import { PlayerError, PlayerErrorCode, createPlayerError } from '../common/PlayerError';
import { PlayHistoryService } from '../service/PlayHistoryService';
import { SettingsService } from '../service/SettingsService';
import { QualityOption } from '../model/OnlineMedia';
import { LocalizationManager } from '../utils/LocalizationManager';
import { DanmakuEngine } from '../utils/DanmakuEngine';
import { PiPManager, PiPState } from '../service/PiPManager';

interface ErrorWithCode extends Error {
  code: number;
}

interface SubtitleCue {
  startMs: number;
  endMs: number;
  text: string;
}

function mapIjkError(what: number, extra: number): PlayerErrorCode {
  // Common IjkPlayer error codes
  if (extra === -2) return PlayerErrorCode.FILE_NOT_FOUND;
  if (extra === -5) return PlayerErrorCode.FILE_READ_ERROR;
  if (extra === -13) return PlayerErrorCode.PERMISSION_DENIED;
  if (extra === -110) return PlayerErrorCode.NETWORK_TIMEOUT;
  if (extra === -111) return PlayerErrorCode.NETWORK_CONNECTION_CLOSED;
  if (extra === -12) return PlayerErrorCode.DECODER_INIT_FAILED;
  if (what === -10000 && extra === 0) return PlayerErrorCode.INIT_FAILED;
  return PlayerErrorCode.UNKNOWN;
}

const VIDEO_SURFACE_COMPONENT_ID: string = 'video_player_surface';
const VIDEO_SURFACE_LIBRARY_NAME: string = 'ijkplayer_napi';
const MEDIA_INFO_VIDEO_RENDERING_START: number = 3;
const MEDIA_INFO_BUFFERING_START: number = 701;
const MEDIA_INFO_BUFFERING_END: number = 702;
const MEDIA_INFO_VIDEO_SEEK_RENDERING_START: number = 10008;
const MEDIA_INFO_AUDIO_SEEK_RENDERING_START: number = 10009;
const MEDIA_INFO_MEDIA_ACCURATE_SEEK_COMPLETE: number = 10100;
const SUBTITLE_EXTENSIONS: string[] = ['.ass', '.ssa', '.srt', '.vtt'];
const SUBTITLE_ENCODINGS: string[] = ['utf-8', 'utf-16le', 'utf-16be', 'gb18030', 'gbk', 'big5'];
const RESUME_MIN_POSITION_MS: number = 5000;
const RESUME_END_GUARD_MS: number = 3000;
const RESUME_FLOW_TAG: string = '[ResumeFlow]';

@Component
export struct VideoPlayerView {
  @Prop videoPath: string;
  @Prop videoTitle: string;
  @Prop videoId: string;

  @Prop seekTo: number = 0;
  @Prop qualities: QualityOption[] = [];
  @State currentQualityLabel: string = 'Auto';
  onBack: () => void = () => {};
  onNext: () => void = () => {};
  onPrevious: () => void = () => {};

  @StorageLink('appLanguage') appLanguage: AppLanguage = AppLanguage.SYSTEM;
  private loc: LocalizationManager = LocalizationManager.getInstance();

  @State playerManager: VideoPlayerManager = new VideoPlayerManager();
  @State playerState: PlayerState = PlayerState.IDLE;
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPlaying: boolean = false;
  @State isBuffering: boolean = false;
  @State currentSpeed: PlaybackSpeed = PlaybackSpeed.SPEED_1_0;
  @State isMuted: boolean = false;
  @State isFullscreen: boolean = false;
  @State showErrorDialog: boolean = false;
  @State showErrorToast: boolean = false;
  @State showDetail: boolean = false;
  @State currentError: PlayerError | null = null;
  @State toastMessage: string = '';
  @State engineType: string = 'IjkPlayer';
  @State videoAspectRatio: number = 16 / 9;
  @State subtitleText: string = '';
  @State subtitlesEnabled: boolean = true;
  @State subtitleDelayMs: number = 0;
  @State screenBrightness: number = 0.5;
  @State playbackVolume: number = 1.0;
  @State danmakuEnabled: boolean = false;
  @State isPiPActive: boolean = false;

  // Danmaku
  private danmakuEngine: DanmakuEngine = new DanmakuEngine();
  // PiP
  private pipManager: PiPManager = PiPManager.getInstance();

  private saveTimerId: number = -1;
  private progressTimerId: number = -1;
  private xComponentController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private managerInitialized: boolean = false;
  private playbackStarted: boolean = false;
  private playbackStarting: boolean = false;
  private pendingStartToken: number = 0;
  private ijkPlayer: IjkMediaPlayer = new IjkMediaPlayer(VIDEO_SURFACE_COMPONENT_ID);
  private nativeContext: Object | undefined = undefined;
  private useAvPlayerEngine: boolean = false;
  private timedTextReady: boolean = false;
  private externalSubtitleCues: SubtitleCue[] = [];
  private pendingResumePosition: number = 0;
  private hasAppliedResumeSeek: boolean = false;

  async aboutToAppear(): Promise<void> {
    console.info('[VideoPlayerView] aboutToAppear - videoPath:', this.videoPath);
    console.info('[VideoPlayerView] aboutToAppear - videoTitle:', this.videoTitle);
    console.info('[VideoPlayerView] aboutToAppear - videoId:', this.videoId);
    console.info(RESUME_FLOW_TAG + ' aboutToAppear seekTo=' + this.seekTo + ' videoId=' + this.videoId + ' path=' + this.videoPath);

    this.pendingResumePosition = this.seekTo;
    this.hasAppliedResumeSeek = false;
    this.subtitlesEnabled = await SettingsService.getInstance().getShowSubtitle();
    this.useAvPlayerEngine = await SettingsService.getInstance().getHwAcceleration();
    this.pipManager.setContext(getContext(this) as common.UIAbilityContext);
    this.pipManager.setCallbacks({
      onStateChange: (state: PiPState) => {
        this.isPiPActive = state === PiPState.ACTIVE;
      }
    });
    await this.loadExternalSubtitles();
    await this.initPlayerManager();
    await this.startPlaybackIfReady();
  }

  async aboutToDisappear(): Promise<void> {
    this.pendingStartToken++;
    this.currentTime = this.ijkPlayer.getCurrentPosition();
    this.duration = this.ijkPlayer.getDuration();
    this.stopProgressTimer();
    if (this.saveTimerId >= 0) {
      clearInterval(this.saveTimerId);
      this.saveTimerId = -1;
    }
    this.managerInitialized = false;
    this.playbackStarted = false;
    this.playbackStarting = false;
    this.isBuffering = false;
    this.subtitleText = '';
    // Exit PiP if active
    if (this.isPiPActive) {
      this.pipManager.exitPiP();
      this.isPiPActive = false;
    }
    try {
      if (this.engineType === 'AVPlayer') {
        await this.playerManager.release();
      } else {
        this.ijkPlayer.release();
      }
    } catch (error) {
      console.warn('[VideoPlayerView] player release failed');
    }
    await this.saveProgress();
    await this.playerManager.release();
  }

  private async initPlayerManager(): Promise<void> {
    this.playerManager.setAbilityContext(getContext(this) as common.UIAbilityContext);
    await this.playerManager.init({
      onError: (error: PlayerError) => {
        console.error('[VideoPlayerView] onError callback - code:', error.code, 'message:', error.message);
        this.handleError(error);
      }
    });

    this.ijkPlayer.setOnPreparedListener({
      onPrepared: () => {
        this.playerState = PlayerState.PREPARED;
        this.duration = this.ijkPlayer.getDuration();
        this.isBuffering = false;
        this.engineType = 'IjkPlayer';
        this.applyResumeSeekIfNeeded();
        this.updateExternalSubtitleForCurrentTime();
        console.info('[VideoPlayerView] ijk prepared, duration:', this.duration);
      }
    } as OnPreparedListener);

    this.ijkPlayer.setOnCompletionListener({
      onCompletion: () => {
        this.playerState = PlayerState.COMPLETED;
        this.isPlaying = false;
        this.isBuffering = false;
        this.subtitleText = '';
        this.stopProgressTimer();
        this.saveProgress();
      }
    } as OnCompletionListener);

    this.ijkPlayer.setOnBufferingUpdateListener({
      onBufferingUpdate: (percent: number) => {
        console.info('[VideoPlayerView] ijk buffering percent:', percent);
      }
    } as OnBufferingUpdateListener);

    this.ijkPlayer.setOnSeekCompleteListener({
      onSeekComplete: () => {
        this.currentTime = this.ijkPlayer.getCurrentPosition();
        console.info(RESUME_FLOW_TAG + ' onSeekComplete currentTime=' + this.currentTime);
        this.isBuffering = false;
        this.updateExternalSubtitleForCurrentTime();
        if (this.isPlaying) {
          this.playerState = PlayerState.PLAYING;
        }
      }
    } as OnSeekCompleteListener);

    this.ijkPlayer.setOnVideoSizeChangedListener({
      onVideoSizeChanged: (width: number, height: number) => {
        if (width > 0 && height > 0) {
          this.videoAspectRatio = width / height;
        }
      }
    } as OnVideoSizeChangedListener);

    this.ijkPlayer.setOnInfoListener({
      onInfo: (what: number, extra: number) => {
        // console.info('[VideoPlayerView] ijk info what=' + what + ' extra=' + extra);
        switch (what) {
          case MEDIA_INFO_BUFFERING_START:
            this.isBuffering = this.isPlaying;
            break;
          case MEDIA_INFO_BUFFERING_END:
          case MEDIA_INFO_VIDEO_RENDERING_START:
          case MEDIA_INFO_VIDEO_SEEK_RENDERING_START:
          case MEDIA_INFO_AUDIO_SEEK_RENDERING_START:
          case MEDIA_INFO_MEDIA_ACCURATE_SEEK_COMPLETE:
            this.isBuffering = false;
            if (this.isPlaying) {
              this.playerState = PlayerState.PLAYING;
            }
            this.currentTime = this.ijkPlayer.getCurrentPosition();
            this.updateExternalSubtitleForCurrentTime();
            break;
          default:
            break;
        }
      }
    } as OnInfoListener);

    this.ijkPlayer.setOnTimedTextListener({
      onTimedText: (text: string) => {
        console.info('[VideoPlayerView] subtitle timed text raw=' + JSON.stringify(text));
        if (this.hasExternalSubtitles()) {
          console.info('[VideoPlayerView] subtitle timed text ignored because external subtitles are active');
          return;
        }
        this.timedTextReady = true;
        if (!this.subtitlesEnabled) {
          console.info('[VideoPlayerView] subtitle timed text ignored because subtitles are disabled');
          this.subtitleText = '';
          return;
        }
        this.subtitleText = this.normalizeSubtitleText(text);
        console.info('[VideoPlayerView] subtitle timed text normalized=' + JSON.stringify(this.subtitleText));
      }
    } as OnTimedTextListener);

    this.ijkPlayer.setOnErrorListener({
      onError: (what: number, extra: number) => {
        console.error(`[VideoPlayerView] ijk error what=${what} extra=${extra}`);
        this.stopProgressTimer();
        this.isPlaying = false;
        this.isBuffering = false;
        this.subtitleText = '';
        this.playerState = PlayerState.ERROR;
        this.handleError(createPlayerError(mapIjkError(what, extra),
          `IjkPlayer error: what=${what}, extra=${extra}. Path: ${this.videoPath}`));
      }
    } as OnErrorListener);

    this.ijkPlayer.setMessageListener();
    this.managerInitialized = true;
    console.info('[VideoPlayerView] engine type:', this.engineType);
  }

  private applyResumeSeekIfNeeded(): void {
    if (this.hasAppliedResumeSeek) {
      return;
    }
    if (this.pendingResumePosition < RESUME_MIN_POSITION_MS) {
      return;
    }
    if (this.duration > 0 && this.pendingResumePosition >= this.duration - RESUME_END_GUARD_MS) {
      console.info(RESUME_FLOW_TAG + ' skip resume seek near end pendingResumePosition=' + this.pendingResumePosition + ' duration=' + this.duration);
      this.clearResumePosition();
      return;
    }
    try {
      this.hasAppliedResumeSeek = true;
      console.info(RESUME_FLOW_TAG + ' apply resume seekTo=' + this.pendingResumePosition + ' duration=' + this.duration);
      this.ijkPlayer.seekTo(`${this.pendingResumePosition}`);
    } catch (error) {
      console.warn('[VideoPlayerView] apply resume seek failed');
    }
  }

  /**
   * Check if file format is AVPlayer-friendly
   */
  private isAvPlayerFormat(path: string): boolean {
    const lower = path.toLowerCase();
    const avFormats: string[] = ['.mp4', '.m4v', '.mov', '.3gp', '.ts'];
    for (const fmt of avFormats) {
      if (lower.endsWith(fmt)) return true;
    }
    return false;
  }

  /**
   * Attempt playback via VideoPlayerManager (AVPlayer engine)
   */
  private async tryAvPlayerPlayback(): Promise<boolean> {
    try {
      this.currentError = null;
      this.showErrorDialog = false;
      this.subtitleText = '';

      this.playerManager.setAbilityContext(getContext(this) as common.UIAbilityContext);
      await this.playerManager.init({
        onError: (error: PlayerError) => {
          console.error('[VideoPlayerView] AVPlayer error:', error.message);
          this.handleError(error);
        }
      }, PlaybackEngine.AVPLAYER);

      // Set surface for AVPlayer
      if (this.surfaceId.length > 0) {
        this.playerManager.setSurface(this.surfaceId);
      }

      await this.playerManager.setSource(this.videoPath);
      this.playerManager.setDisplaySurface(this.surfaceId);

      // Set speed before playing
      await this.playerManager.setSpeed(this.currentSpeed);

      // Apply resume seek if needed
      if (this.pendingResumePosition > 0) {
        await this.playerManager.play();
        await new Promise<void>((resolve) => setTimeout(resolve, 300));
        await this.playerManager.seekTo(this.pendingResumePosition);
        this.hasAppliedResumeSeek = true;
        this.clearResumePosition();
      } else {
        await this.playerManager.play();
      }

      this.playerState = PlayerState.PLAYING;
      this.isPlaying = true;
      this.playbackStarted = true;
      this.engineType = 'AVPlayer';

      // Start progress polling for AVPlayer
      this.startProgressTimer();
      return true;
    } catch (error) {
      console.error('[VideoPlayerView] AVPlayer setup failed: ' + JSON.stringify(error));
      await this.playerManager.release();
      return false;
    }
  }

  private clearResumePosition(): void {
    this.pendingResumePosition = 0;
    this.hasAppliedResumeSeek = true;
  }
  private async startPlaybackIfReady(): Promise<void> {
    if (!this.managerInitialized || this.playbackStarted || this.playbackStarting) {
      return;
    }

    if (this.videoPath.length === 0) {
      console.warn('[VideoPlayerView] waiting for videoPath before playback');
      return;
    }

    if (this.nativeContext === undefined) {
      console.info('[VideoPlayerView] waiting for render surface before playback');
      return;
    }

    const token = ++this.pendingStartToken;
    await new Promise<void>((resolve) => setTimeout(resolve, 250));

    if (token !== this.pendingStartToken || !this.managerInitialized || this.playbackStarted || this.playbackStarting) {
      return;
    }

    // Try AVPlayer first if HW acceleration is enabled and format is AVPlayer-friendly
    if (this.useAvPlayerEngine && this.isAvPlayerFormat(this.videoPath)) {
      const avSuccess = await this.tryAvPlayerPlayback();
      if (avSuccess) {
        console.info('[VideoPlayerView] using AVPlayer engine');
        return;
      }
      console.warn('[VideoPlayerView] AVPlayer failed, falling back to ijkplayer');
    }

    try {
      this.playbackStarting = true;
      this.currentError = null;
      this.showErrorDialog = false;
      this.subtitleText = '';
      this.timedTextReady = false;
      // 1. Set rendering context first
      this.ijkPlayer.setContext(this.nativeContext, VIDEO_SURFACE_COMPONENT_ID);
      // 2. Create native player BEFORE any other operations
      this.ijkPlayer.native_setup(VideoCodecMode.SURFACE);
      // 3. Now safe to configure the player
      this.ijkPlayer.reset();
      this.ijkPlayer.setDebug(true);
      this.ijkPlayer.setVolume(this.isMuted ? '0' : '1.0', this.isMuted ? '0' : '1.0');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'enable-accurate-seek', '1');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'max-buffer-size', '102400');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'min-frames', '100');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '1');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'packet-buffering', '0');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'framedrop', '5');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'max_cached_duration', '3000');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'soundtouch', '1');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-all-videos', '1');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-hevc', '1');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'overlay-format', '842094158');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'subtitle', this.subtitlesEnabled ? '1' : '0');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'timeout', '10000000');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'connect_timeout', '10000000');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'addrinfo_timeout', '10000000');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'dns_cache_timeout', '10000000');
      this.ijkPlayer.setSpeed(`${this.currentSpeed}f`);
      this.ijkPlayer.setLoopCount(false);
      this.ijkPlayer.setScreenOnWhilePlaying(true);
      this.ijkPlayer.setDataSource(this.videoPath);
      this.ijkPlayer.setMessageListener();
      this.ijkPlayer.prepareAsync();
      this.ijkPlayer.start();
      this.playerState = PlayerState.PLAYING;
      this.isPlaying = true;
      this.playbackStarted = true;
      this.startProgressTimer();
      console.info('[VideoPlayerView] ijk play() called successfully');
    } catch (error) {
      const err = error as ErrorWithCode;
      console.error('[VideoPlayerView] ijk setup failed:', JSON.stringify(err));
      this.handleError(createPlayerError(PlayerErrorCode.UNKNOWN,
        `Ijk setup failed: ${err.message}. Path=${this.videoPath}`));
    } finally {
      this.playbackStarting = false;
    }
  }

  private startProgressTimer(): void {
    this.stopProgressTimer();
    // Start danmaku engine with current time
    this.danmakuEngine.start(this.currentTime);
    this.progressTimerId = setInterval(() => {
      if (this.engineType === 'AVPlayer') {
        this.currentTime = this.playerManager.currentTime;
        this.duration = this.playerManager.duration;
        this.isBuffering = this.playerManager.isBuffering;
        this.playerState = this.playerManager.state;
      } else {
        this.currentTime = this.ijkPlayer.getCurrentPosition();
        this.duration = this.ijkPlayer.getDuration();
      }
      if (this.hasExternalSubtitles()) {
        this.updateExternalSubtitleForCurrentTime();
      }
      // Sync danmaku engine
      if (this.danmakuEnabled) {
        this.danmakuEngine.update(this.currentTime, 250);
      }
      if (this.saveTimerId < 0) {
        this.saveTimerId = setInterval(() => {
          this.saveProgress();
        }, 5000);
      }
    }, 250);
  }

  private stopProgressTimer(): void {
    if (this.progressTimerId >= 0) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
    }
  }

  private handleSurfaceReady(nativeContext?: Object): void {
    this.surfaceId = this.xComponentController.getXComponentSurfaceId();
    this.nativeContext = nativeContext;
    console.info('[VideoPlayerView] XComponent surface loaded:', this.surfaceId);
    this.startPlaybackIfReady();
  }

  private handleSurfaceDestroyed(): void {
    console.info('[VideoPlayerView] XComponent surface destroyed');
    this.surfaceId = '';
    this.nativeContext = undefined;
    this.isBuffering = false;
    this.subtitleText = '';
    this.stopProgressTimer();
  }

  private handleError(error: PlayerError): void {
    console.error(`[VideoPlayerView] handleError - code: ${error.code}, title: ${error.title}`);
    console.error(`[VideoPlayerView] handleError - message: ${error.message}`);
    this.currentError = error;
    this.showErrorDialog = true;
  }

  private async retryPlay(): Promise<void> {
    this.currentError = null;
    this.showErrorDialog = false;
    this.playbackStarted = false;
    this.playbackStarting = false;
    this.stopProgressTimer();
    this.subtitleText = '';
    this.pendingResumePosition = this.seekTo;
    this.hasAppliedResumeSeek = false;

    try {
      this.ijkPlayer.reset();
      await this.startPlaybackIfReady();
    } catch (error) {
      this.handleError(createPlayerError(PlayerErrorCode.UNKNOWN, this.loc.getString('error_retry_failed')));
    }
  }

  private togglePlayback(): void {
    if (this.engineType === 'AVPlayer') {
      if (this.isPlaying) {
        this.playerManager.pause();
        this.playerState = PlayerState.PAUSED;
        this.isPlaying = false;
        this.isBuffering = false;
      } else {
        this.playerManager.play();
        this.playerState = PlayerState.PLAYING;
        this.isPlaying = true;
      }
      this.pipManager.updatePlayState(this.isPlaying, this.videoTitle);
      return;
    }

    if (this.isPlaying) {
      this.ijkPlayer.pause();
      this.playerState = PlayerState.PAUSED;
      this.isPlaying = false;
      this.isBuffering = false;
      this.pipManager.updatePlayState(false, this.videoTitle);
      return;
    }
    this.ijkPlayer.start();
    this.playerState = PlayerState.PLAYING;
    this.isPlaying = true;
    this.pipManager.updatePlayState(true, this.videoTitle);
  }

  private async saveProgress(): Promise<void> {
    if (this.duration <= 0) return;

    const shouldClearProgress = this.currentTime >= this.duration - RESUME_END_GUARD_MS;
    const positionToSave = shouldClearProgress ? 0 : this.currentTime;

    try {
      console.info(RESUME_FLOW_TAG + ' saveProgress videoId=' + this.videoId + ' path=' + this.videoPath + ' currentTime=' + this.currentTime + ' duration=' + this.duration + ' positionToSave=' + positionToSave);
      await PlayHistoryService.getInstance().saveRecord({
        videoId: this.videoId,
        title: this.videoTitle,
        path: this.videoPath,
        lastPosition: positionToSave,
        duration: this.duration,
        timestamp: Date.now()
      });
    } catch (error) {
      console.warn('Save progress failed.');
    }
  }

  private hasExternalSubtitles(): boolean {
    return this.externalSubtitleCues.length > 0;
  }

  private async loadExternalSubtitles(): Promise<void> {
    this.externalSubtitleCues = [];

    // Skip file-based subtitle scanning for URLs
    if (this.videoPath.startsWith('http://') || this.videoPath.startsWith('https://')) {
      console.info('[VideoPlayerView] online video, skipping local subtitle scan');
      return;
    }

    for (const extension of SUBTITLE_EXTENSIONS) {
      const subtitlePath = this.getSubtitlePathByExtension(extension);
      try {
        if (!fileIo.accessSync(subtitlePath)) {
          continue;
        }
        const text = this.readSubtitleSourceText(subtitlePath);
        const cues = this.parseSubtitleByExtension(extension, text);
        if (cues.length > 0) {
          this.externalSubtitleCues = cues;
          console.info('[VideoPlayerView] loaded external subtitle path=' + subtitlePath + ' cueCount=' + cues.length);
          return;
        }
      } catch (error) {
        console.warn('[VideoPlayerView] load subtitle failed for path=' + subtitlePath);
      }
    }
  }

  private parseSubtitleByExtension(extension: string, content: string): SubtitleCue[] {
    switch (extension) {
      case '.ass':
      case '.ssa':
        return this.parseAss(content);
      case '.vtt':
        return this.parseVtt(content);
      default:
        return this.parseSrt(content);
    }
  }

  private readSubtitleSourceText(subtitlePath: string): string {
    const subtitleFile = fileIo.openSync(subtitlePath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(subtitlePath);
      const byteLength = Number(stat.size);
      if (byteLength <= 0) {
        return '';
      }
      const arrayBuffer = new ArrayBuffer(byteLength);
      const bytesRead = fileIo.readSync(subtitleFile.fd, arrayBuffer);
      const bytes = new Uint8Array(arrayBuffer, 0, bytesRead);
      return this.decodeSubtitleBytes(bytes);
    } finally {
      fileIo.closeSync(subtitleFile);
    }
  }

  private decodeSubtitleBytes(bytes: Uint8Array): string {
    let bestText: string = '';
    let bestScore: number = Number.NEGATIVE_INFINITY;
    for (const encoding of SUBTITLE_ENCODINGS) {
      try {
        const decoder = util.TextDecoder.create(encoding, { fatal: false, ignoreBOM: false });
        const decoded = decoder.decode(bytes);
        const score = this.scoreDecodedSubtitleText(decoded);
        if (score > bestScore) {
          bestScore = score;
          bestText = decoded;
        }
      } catch (error) {
        console.warn('[VideoPlayerView] subtitle decode failed for encoding:', encoding);
      }
    }
    return bestText;
  }

  private scoreDecodedSubtitleText(text: string): number {
    const replacementCount = (text.match(/\uFFFD/g) ?? []).length;
    const cueCount = (text.match(/-->|Dialogue:/g) ?? []).length;
    const cjkCount = (text.match(/[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]/g) ?? []).length;
    const controlCount = (text.match(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g) ?? []).length;
    return cueCount * 1000 + cjkCount * 10 - replacementCount * 200 - controlCount * 100;
  }

  private getSubtitlePathByExtension(extension: string): string {
    const lastDot = this.videoPath.lastIndexOf('.');
    const basePath = lastDot >= 0 ? this.videoPath.substring(0, lastDot) : this.videoPath;
    return `${basePath}${extension}`;
  }

  private parseSrt(content: string): SubtitleCue[] {
    const normalized = content.replace(/\r/g, '');
    const blocks = normalized.split('\n\n');
    const cues: SubtitleCue[] = [];
    for (const block of blocks) {
      const lines = block.split('\n').map((line: string) => line.trim());
      if (lines.length < 2) {
        continue;
      }
      const timeLineIndex = lines[0].includes('-->') ? 0 : 1;
      if (timeLineIndex >= lines.length) {
        continue;
      }
      const timeLine = lines[timeLineIndex];
      if (!timeLine.includes('-->')) {
        continue;
      }
      const textLines = lines.slice(timeLineIndex + 1).filter((line: string) => line.length > 0);
      const cue = this.parseSubtitleCue(timeLine, textLines, ',');
      if (cue) {
        cues.push(cue);
      }
    }
    return cues;
  }

  private parseVtt(content: string): SubtitleCue[] {
    const normalized = content.replace(/\r/g, '');
    const blocks = normalized.split('\n\n');
    const cues: SubtitleCue[] = [];
    for (const block of blocks) {
      const lines = block.split('\n').map((line: string) => line.trim()).filter((line: string) => line.length > 0);
      if (lines.length === 0 || lines[0] === 'WEBVTT') {
        continue;
      }
      const timeLineIndex = lines[0].includes('-->') ? 0 : 1;
      if (timeLineIndex >= lines.length) {
        continue;
      }
      const timeLine = lines[timeLineIndex];
      if (!timeLine.includes('-->')) {
        continue;
      }
      const textLines = lines.slice(timeLineIndex + 1).filter((line: string) => !line.startsWith('NOTE'));
      const cue = this.parseSubtitleCue(timeLine, textLines, '.');
      if (cue) {
        cues.push(cue);
      }
    }
    return cues;
  }

  private parseAss(content: string): SubtitleCue[] {
    const lines = content.replace(/\r/g, '').split('\n');
    const cues: SubtitleCue[] = [];
    let inEvents: boolean = false;
    let formatFields: string[] = [];
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('[')) {
        inEvents = line === '[Events]';
        continue;
      }
      if (!inEvents) {
        continue;
      }
      if (line.startsWith('Format:')) {
        formatFields = line.substring('Format:'.length)
          .split(',')
          .map((field: string) => field.trim().toLowerCase());
        continue;
      }
      if (line.startsWith('Dialogue:')) {
        const cue = this.parseAssDialogue(line.substring('Dialogue:'.length).trim(), formatFields);
        if (cue) {
          cues.push(cue);
        }
      }
    }
    return cues;
  }

  private parseAssDialogue(dialogue: string, formatFields: string[]): SubtitleCue | null {
    const fallbackFields = ['layer', 'start', 'end', 'style', 'name', 'marginl', 'marginr', 'marginv', 'effect', 'text'];
    const fields = formatFields.length > 0 ? formatFields : fallbackFields;
    const expectedParts = fields.length;
    const parts: string[] = [];
    let remaining = dialogue;
    for (let index = 0; index < expectedParts - 1; index++) {
      const commaIndex = remaining.indexOf(',');
      if (commaIndex < 0) {
        return null;
      }
      parts.push(remaining.substring(0, commaIndex).trim());
      remaining = remaining.substring(commaIndex + 1);
    }
    parts.push(remaining);

    const startIndex = fields.indexOf('start');
    const endIndex = fields.indexOf('end');
    const textIndex = fields.indexOf('text');
    if (startIndex < 0 || endIndex < 0 || textIndex < 0) {
      return null;
    }
    const startMs = this.parseSubtitleTimestamp(parts[startIndex].trim(), '.');
    const endMs = this.parseSubtitleTimestamp(parts[endIndex].trim(), '.');
    const text = this.normalizeSubtitleText(parts[textIndex]);
    if (startMs < 0 || endMs <= startMs || text.length === 0) {
      return null;
    }
    return { startMs, endMs, text };
  }

  private parseSubtitleCue(timeLine: string, textLines: string[], millisecondSeparator: string): SubtitleCue | null {
    const segments = timeLine.split('-->');
    if (segments.length < 2) {
      return null;
    }
    const startMs = this.parseSubtitleTimestamp(segments[0].trim(), millisecondSeparator);
    const endMs = this.parseSubtitleTimestamp(segments[1].trim().split(' ')[0], millisecondSeparator);
    const text = this.normalizeSubtitleText(textLines.join('\n'));
    if (startMs < 0 || endMs <= startMs || text.length === 0) {
      return null;
    }
    return { startMs, endMs, text };
  }

  private parseSubtitleTimestamp(timestamp: string, millisecondSeparator: string): number {
    const mainAndFraction = timestamp.split(millisecondSeparator);
    if (mainAndFraction.length !== 2) {
      return -1;
    }
    const parts = mainAndFraction[0].split(':').map((item: string) => Number(item));
    if (parts.length < 2 || parts.length > 3 || parts.some((value: number) => Number.isNaN(value))) {
      return -1;
    }
    const fraction = Number(mainAndFraction[1].substring(0, 3).padEnd(3, '0'));
    if (Number.isNaN(fraction)) {
      return -1;
    }
    const hours = parts.length === 3 ? parts[0] : 0;
    const minutes = parts.length === 3 ? parts[1] : parts[0];
    const seconds = parts.length === 3 ? parts[2] : parts[1];
    return (((hours * 60) + minutes) * 60 + seconds) * 1000 + fraction;
  }

  private normalizeSubtitleText(text: string): string {
    let cleaned = text
      .replace(/^\uFEFF/, '')
      .replace(/[\uD800-\uDFFF]/g, '')
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/g, '')
      .replace(/\r/g, '')
      .replace(/\\N/gi, '\n')
      .replace(/\\h/gi, ' ')
      .replace(/\{[^}]*\}/g, '')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&#(\d+);/g, (_match: string, dec: string) => String.fromCharCode(Number(dec)))
      .replace(/&#x([0-9a-fA-F]+);/g, (_match: string, hex: string) => String.fromCharCode(parseInt(hex, 16)))
      .replace(/[\u200B-\u200D\u2060]/g, '')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    const lastBraceIndex = cleaned.lastIndexOf('}');
    if (lastBraceIndex >= 0 && lastBraceIndex < cleaned.length - 1) {
      const tail = cleaned.substring(lastBraceIndex + 1).trim();
      if (/[A-Za-z\u3400-\u4dbf\u4e00-\u9fff]/.test(tail)) {
        cleaned = tail;
      }
    }
    return this.stripSubtitleArtifacts(cleaned);
  }

  private stripSubtitleArtifacts(text: string): string {
    const lines = text.split('\n').map((line: string) => {
      let current = line.trim();
      const hanIndex = current.search(/[\u3400-\u4dbf\u4e00-\u9fff]/);
      if (hanIndex > 0) {
        current = current.substring(hanIndex);
      } else {
        const alphaIndex = current.search(/[A-Za-z]/);
        if (alphaIndex > 0 && alphaIndex <= 32) {
          const prefix = current.substring(0, alphaIndex);
          if (/[^A-Za-z0-9\s'"(\[【‘’“”.,:;!?-]/.test(prefix) || prefix.includes('\uFFFD')) {
            current = current.substring(alphaIndex);
          }
        }
      }
      current = current
        .replace(/^[^A-Za-z\u3400-\u4dbf\u4e00-\u9fff]+(?=[A-Za-z\u3400-\u4dbf\u4e00-\u9fff])/, '')
        .replace(/\uFFFD+/g, '')
        .trim();
      const mixedGarbageMatch = current.match(/^[\u3400-\u4dbf\u4e00-\u9fff]{1,2}[A-Za-z]{1,4}$|^[A-Za-z]{1,4}[\u3400-\u4dbf\u4e00-\u9fff]{1,2}$/);
      if (mixedGarbageMatch) {
        return '';
      }
      return current;
    }).filter((line: string) => line.length > 0);
    return lines.join('\n');
  }

  private updateExternalSubtitleForCurrentTime(): void {
    if (!this.subtitlesEnabled) {
      this.subtitleText = '';
      return;
    }
    if (!this.hasExternalSubtitles()) {
      return;
    }
    const adjustedTime = this.currentTime - this.subtitleDelayMs;
    const currentCue = this.externalSubtitleCues.find((cue: SubtitleCue) =>
      adjustedTime >= cue.startMs && adjustedTime <= cue.endMs);
    const nextSubtitleText = currentCue ? currentCue.text : '';
    if (nextSubtitleText !== this.subtitleText) {
      console.info('[VideoPlayerView] subtitle external currentTime=' + this.currentTime + ' delay=' + this.subtitleDelayMs + ' text=' + JSON.stringify(nextSubtitleText));
    }
    this.subtitleText = nextSubtitleText;
  }

  /**
   * 手动选择外挂字幕文件
   */
  async selectSubtitleFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select();
      if (result.length === 0) {
        return;
      }
      const subtitlePath = result[0];
      const text = this.readSubtitleSourceText(subtitlePath);
      const extension = subtitlePath.substring(subtitlePath.lastIndexOf('.')).toLowerCase();
      const cues = this.parseSubtitleByExtension(extension, text);
      if (cues.length > 0) {
        this.externalSubtitleCues = cues;
        this.subtitleDelayMs = 0;
        console.info('[VideoPlayerView] manual subtitle loaded: ' + subtitlePath + ' cues=' + cues.length);
      } else {
        console.warn('[VideoPlayerView] no cues found in selected subtitle file');
      }
    } catch (error) {
      console.error('[VideoPlayerView] select subtitle failed: ' + JSON.stringify(error));
    }
  }

  /**
   * 切换清晰度（由父组件通过 router.replaceUrl 重新加载，此处仅更新标记）
   */
  private markQualitySwitch(label: string): void {
    this.currentQualityLabel = label;
  }
  setSubtitleDelay(delayMs: number): void {
    this.subtitleDelayMs = delayMs;
    console.info('[VideoPlayerView] subtitle delay set to ' + delayMs + 'ms');
  }

  /**
   * Toggle danmaku on/off
   */
  toggleDanmaku(): void {
    this.danmakuEnabled = !this.danmakuEnabled;
    this.danmakuEngine.config.enabled = this.danmakuEnabled;
  }

  /**
   * Send a danmaku comment
   */
  sendDanmaku(text: string): void {
    if (text.trim().length > 0) {
      this.danmakuEngine.sendDanmaku(text.trim());
    }
  }

  /**
   * Toggle Picture-in-Picture mode
   */
  async togglePiP(): Promise<void> {
    if (this.isPiPActive) {
      await this.pipManager.exitPiP();
    } else {
      const entered = await this.pipManager.enterPiP(this.videoTitle, this.isPlaying);
      if (entered) {
        this.isPiPActive = true;
      }
    }
  }

  /**
   * 设置屏幕亮度
   */
  private setScreenBrightness(brightness: number): void {
    this.screenBrightness = brightness;
    window.getLastWindow(getContext(this)).then((win) => {
      win.setWindowBrightness(brightness);
    }).catch((err: Error) => {
      console.warn('[VideoPlayerView] set brightness failed: ' + err.message);
    });
  }

  /**
   * 设置播放音量
   */
  private setPlaybackVolume(vol: number): void {
    this.playbackVolume = vol;
    const volStr = vol.toFixed(1);
    this.ijkPlayer.setVolume(volStr, volStr);
  }

  build() {
    Stack() {
      XComponent({
        id: VIDEO_SURFACE_COMPONENT_ID,
        type: XComponentType.SURFACE,
        libraryname: VIDEO_SURFACE_LIBRARY_NAME,
        controller: this.xComponentController
      })
        .width('100%')
        .aspectRatio(this.videoAspectRatio)
        .backgroundColor($r('sys.color.black'))
        .onLoad((nativeContext?: Object) => {
          this.handleSurfaceReady(nativeContext);
        })
        .onDestroy(() => {
          this.handleSurfaceDestroyed();
        })

      // Danmaku layer (between video and subtitles)
      DanmakuLayer({ engine: this.danmakuEngine })

      if (this.subtitlesEnabled && this.subtitleText.length > 0) {
        Column() {
          Blank()
          Text(this.subtitleText)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor('rgba(0,0,0,0.55)')
            .borderRadius(6)
            .margin({ left: 20, right: 20, bottom: 92 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
      }

      ControlPanel({
        title: this.videoTitle,
        currentTime: this.currentTime,
        duration: this.duration,
        isPlaying: this.isPlaying,
        playerState: this.playerState,
        currentSpeed: this.currentSpeed,
        isMuted: this.isMuted,
        isBuffering: this.isBuffering,
        panelBrightness: this.screenBrightness,
        volume: this.playbackVolume,
        subtitleDelayMs: this.subtitleDelayMs,
        onPlayPause: async () => {
          this.togglePlayback();
        },
        onSeek: async (timeMs: number) => {
          if (this.isPlaying) {
            this.isBuffering = true;
          }
          if (this.engineType === 'AVPlayer') {
            this.playerManager.seekTo(timeMs);
          } else {
            this.ijkPlayer.seekTo(`${timeMs}`);
          }
        },
        onSeekForward: async () => {
          if (this.isPlaying) {
            this.isBuffering = true;
          }
          const targetTime = this.currentTime + 10000;
          if (this.engineType === 'AVPlayer') {
            this.playerManager.seekTo(targetTime);
          } else {
            this.ijkPlayer.seekTo(`${targetTime}`);
          }
        },
        onSeekBackward: async () => {
          if (this.isPlaying) {
            this.isBuffering = true;
          }
          const targetTime = Math.max(0, this.currentTime - 10000);
          if (this.engineType === 'AVPlayer') {
            this.playerManager.seekTo(targetTime);
          } else {
            this.ijkPlayer.seekTo(`${targetTime}`);
          }
        },
        onSpeedChange: async () => {
          const speeds = [PlaybackSpeed.SPEED_0_5, PlaybackSpeed.SPEED_1_0, PlaybackSpeed.SPEED_1_5, PlaybackSpeed.SPEED_2_0];
          const currentIdx = speeds.indexOf(this.currentSpeed);
          const nextSpeed = speeds[(currentIdx + 1) % speeds.length];
          this.currentSpeed = nextSpeed;
          if (this.engineType === 'AVPlayer') {
            this.playerManager.setSpeed(nextSpeed);
          } else {
            this.ijkPlayer.setSpeed(`${nextSpeed}f`);
          }
        },
        onToggleMute: async () => {
          this.isMuted = !this.isMuted;
          if (this.engineType === 'AVPlayer') {
            this.playerManager.setVolume(this.isMuted ? 0 : 1.0);
          } else {
            this.ijkPlayer.setVolume(this.isMuted ? '0' : '1.0', this.isMuted ? '0' : '1.0');
          }
        },
        onBrightnessChange: (brightness: number) => {
          this.setScreenBrightness(brightness);
        },
        onVolumeChange: (volume: number) => {
          this.setPlaybackVolume(volume);
          this.isMuted = volume === 0;
        },
        onGestureSeek: (timeMs: number) => {
          if (this.isPlaying) {
            this.isBuffering = true;
          }
          this.ijkPlayer.seekTo(`${timeMs}`);
        },
        onSubtitleDelayChange: (delayMs: number) => {
          this.setSubtitleDelay(delayMs);
        },
        onLoadSubtitle: () => {
          this.selectSubtitleFile();
        },
        qualities: this.qualities,
        currentQualityLabel: this.currentQualityLabel,
        onQualityChange: (option: QualityOption) => {
          // Quality switching requires parent reload; just mark for now
          this.markQualitySwitch(option.label);
        },
        danmakuEnabled: this.danmakuEnabled,
        onToggleDanmaku: () => {
          this.toggleDanmaku();
        },
        onSendDanmaku: (text: string) => {
          this.sendDanmaku(text);
        },
        isPiPActive: this.isPiPActive,
        onTogglePiP: () => {
          this.togglePiP();
        },
        onPrevious: () => this.onPrevious(),
        onNext: () => this.onNext(),
        onBack: () => this.onBack(),
        onFullscreen: () => {
          this.isFullscreen = !this.isFullscreen;
        }
      })

      if (this.engineType.length > 0) {
        Row() {
          Text(this.engineType)
            .fontSize(10)
            .fontColor('#66FFFFFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('rgba(0,0,0,0.4)')
            .borderRadius(4)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 8, top: 4 })
      }

      ErrorToast({
        visible: this.showErrorToast,
        message: this.toastMessage,
        retryable: true,
        onRetry: () => this.retryPlay(),
        onDismiss: () => {
          this.showErrorToast = false;
        }
      })
        .width('100%')
        .position({ x: 0, y: 48 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.black'))
    .bindSheet($$this.showErrorDialog, this.ErrorSheetBuilder(), {
      height: SheetSize.MEDIUM,
      preferType: SheetType.CENTER,
      maskColor: 'rgba(0,0,0,0.6)',
      showClose: false
    })
  }

  @Builder
  ErrorSheetBuilder() {
    Column({ space: 0 }) {
      Column({ space: 12 }) {
        Stack() {
          Circle()
            .width(64)
            .height(64)
            .fill('#FFF3E0')
          Text('!')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.multi_color_10'))
        }

        Text(this.currentError?.title || this.loc.getString('error_playback_failed'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 24, bottom: 16 })

      Row() {
        Text(`${this.loc.getString('error_code')}: ${this.currentError?.code || 0}`)
          .fontSize(11)
          .fontColor('#999999')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor('#F5F5F5')
          .borderRadius(10)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 16 })

      Divider().color('#F0F0F0').height(1)

      Column({ space: 8 }) {
        Text(this.currentError?.message || this.loc.getString('error_unknown'))
          .fontSize(15)
          .fontColor('#555555')
          .textAlign(TextAlign.Center)
          .padding({ top: 16 })

        if (this.currentError?.suggestion) {
          Text(this.currentError?.suggestion || '')
            .fontSize(13)
            .fontColor('#888888')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24, top: 8 })
        }

        if (this.currentError?.detail) {
          Column() {
            Text(this.showDetail ? this.loc.getString('error_hide_detail') : this.loc.getString('error_show_detail'))
              .fontSize(12)
              .fontColor('#2196F3')
              .onClick(() => {
                this.showDetail = !this.showDetail;
              })

            if (this.showDetail) {
              Text(this.currentError?.detail || '')
                .fontSize(11)
                .fontColor('#777777')
                .fontFamily('monospace')
                .padding(12)
                .width('100%')
                .backgroundColor('#FAFAFA')
                .borderRadius(8)
                .margin({ top: 8 })
                .copyOption(CopyOptions.LocalDevice)
            }
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 12 })
        }
      }
      .padding({ bottom: 20 })

      Divider().color('#F0F0F0').height(1)

      Row({ space: 0 }) {
        Button(this.loc.getString('error_close'))
          .fontSize(15)
          .fontColor('#999999')
          .backgroundColor($r('sys.color.comp_background_list_card'))
          .layoutWeight(1)
          .height(48)
          .type(ButtonType.Normal)
          .borderRadius(0)
          .onClick(() => {
            this.showErrorDialog = false;
          })

        if (this.currentError?.retryable) {
          Divider().vertical(true).color('#F0F0F0').height(32)

          Button(this.loc.getString('error_retry'))
            .fontSize(15)
            .fontColor('#FF4081')
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('sys.color.comp_background_list_card'))
            .layoutWeight(1)
            .height(48)
            .type(ButtonType.Normal)
            .borderRadius(0)
            .onClick(() => {
              this.showErrorDialog = false;
              this.retryPlay();
            })
        }
      }
      .width('100%')
      .height(48)
    }
    .width('100%')
  }
}











