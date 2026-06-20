import { VideoPlayerManager } from '../service/VideoPlayerManager';
import { ControlPanel } from './ControlPanel';
import { ErrorToast } from './ErrorDialog';
import { PlayerState, PlaybackSpeed } from '../common/Enums';
import { PlayerError, PlayerErrorCode, createPlayerError } from '../common/PlayerError';
import { PlayHistoryService } from '../service/PlayHistoryService';
import { common } from '@kit.AbilityKit';
import {
  IjkMediaPlayer,
  OnBufferingUpdateListener,
  OnCompletionListener,
  OnErrorListener,
  OnInfoListener,
  OnPreparedListener,
  OnSeekCompleteListener,
  OnVideoSizeChangedListener,
  VideoCodecMode
} from '@ohos/ijkplayer';

interface ErrorWithCode extends Error {
  code: number;
}

const VIDEO_SURFACE_COMPONENT_ID: string = 'video_player_surface';
const VIDEO_SURFACE_LIBRARY_NAME: string = 'ijkplayer_napi';
const MEDIA_INFO_VIDEO_RENDERING_START: number = 3;
const MEDIA_INFO_BUFFERING_START: number = 701;
const MEDIA_INFO_BUFFERING_END: number = 702;
const MEDIA_INFO_VIDEO_SEEK_RENDERING_START: number = 10008;
const MEDIA_INFO_AUDIO_SEEK_RENDERING_START: number = 10009;
const MEDIA_INFO_MEDIA_ACCURATE_SEEK_COMPLETE: number = 10100;

@Component
export struct VideoPlayerView {
  @Prop videoPath: string;
  @Prop videoTitle: string;
  @Prop videoId: string;

  onBack: () => void = () => {};
  onNext: () => void = () => {};
  onPrevious: () => void = () => {};

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
  @State currentError: PlayerError | null = null;
  @State toastMessage: string = '';
  @State engineType: string = 'IjkPlayer';
  @State videoAspectRatio: number = 16 / 9;

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

  async aboutToAppear(): Promise<void> {
    console.info('[VideoPlayerView] aboutToAppear - videoPath:', this.videoPath);
    console.info('[VideoPlayerView] aboutToAppear - videoTitle:', this.videoTitle);
    console.info('[VideoPlayerView] aboutToAppear - videoId:', this.videoId);

    await this.initPlayerManager();
    await this.startPlaybackIfReady();
  }

  async aboutToDisappear(): Promise<void> {
    this.pendingStartToken++;
    this.stopProgressTimer();
    if (this.saveTimerId >= 0) {
      clearInterval(this.saveTimerId);
      this.saveTimerId = -1;
    }
    this.managerInitialized = false;
    this.playbackStarted = false;
    this.playbackStarting = false;
    this.isBuffering = false;
    try {
      this.ijkPlayer.release();
    } catch (error) {
      console.warn('[VideoPlayerView] ijkPlayer release failed');
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
        console.info('[VideoPlayerView] ijk prepared, duration:', this.duration);
      }
    } as OnPreparedListener);

    this.ijkPlayer.setOnCompletionListener({
      onCompletion: () => {
        this.playerState = PlayerState.COMPLETED;
        this.isPlaying = false;
        this.isBuffering = false;
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
        this.isBuffering = false;
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
        console.info('[VideoPlayerView] ijk info what=' + what + ' extra=' + extra);
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
            break;
          default:
            break;
        }
      }
    } as OnInfoListener);

    this.ijkPlayer.setOnErrorListener({
      onError: (what: number, extra: number) => {
        console.error(`[VideoPlayerView] ijk error what=${what} extra=${extra}`);
        this.stopProgressTimer();
        this.isPlaying = false;
        this.isBuffering = false;
        this.playerState = PlayerState.ERROR;
        this.handleError(createPlayerError(PlayerErrorCode.UNKNOWN,
          `IjkPlayer error: what=${what}, extra=${extra}`));
      }
    } as OnErrorListener);

    this.ijkPlayer.setMessageListener();
    this.managerInitialized = true;
    console.info('[VideoPlayerView] engine type:', this.engineType);
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

    try {
      this.playbackStarting = true;
      this.currentError = null;
      this.showErrorDialog = false;
      this.ijkPlayer.setContext(this.nativeContext, VIDEO_SURFACE_COMPONENT_ID);
      this.ijkPlayer.reset();
      this.ijkPlayer.setDebug(true);
      this.ijkPlayer.native_setup(VideoCodecMode.SURFACE);
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
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'timeout', '10000000');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'connect_timeout', '10000000');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'addrinfo_timeout', '10000000');
      this.ijkPlayer.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'dns_cache_timeout', '10000000');
      this.ijkPlayer.setSpeed(`${this.currentSpeed}`);
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
    this.progressTimerId = setInterval(() => {
      this.currentTime = this.ijkPlayer.getCurrentPosition();
      this.duration = this.ijkPlayer.getDuration();
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

    try {
      this.ijkPlayer.reset();
      await this.startPlaybackIfReady();
    } catch (error) {
      this.handleError(createPlayerError(PlayerErrorCode.UNKNOWN, 'Retry failed.'));
    }
  }

  private async saveProgress(): Promise<void> {
    if (this.duration <= 0) return;

    try {
      await PlayHistoryService.getInstance().saveRecord({
        videoId: this.videoId,
        title: this.videoTitle,
        path: this.videoPath,
        lastPosition: this.currentTime,
        duration: this.duration,
        timestamp: Date.now()
      });
    } catch (error) {
      console.warn('Save progress failed.');
    }
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

      ControlPanel({
        currentTime: this.currentTime,
        duration: this.duration,
        isPlaying: this.isPlaying,
        playerState: this.playerState,
        currentSpeed: this.currentSpeed,
        isMuted: this.isMuted,
        isBuffering: this.isBuffering,
        onPlayPause: async () => {
          if (this.isPlaying) {
            this.ijkPlayer.pause();
            this.playerState = PlayerState.PAUSED;
            this.isPlaying = false;
            this.isBuffering = false;
          } else {
            this.ijkPlayer.start();
            this.playerState = PlayerState.PLAYING;
            this.isPlaying = true;
          }
        },
        onSeek: async (timeMs: number) => {
          if (this.isPlaying) {
            this.isBuffering = true;
          }
          this.ijkPlayer.seekTo(`${timeMs}`);
        },
        onSeekForward: async () => {
          if (this.isPlaying) {
            this.isBuffering = true;
          }
          this.ijkPlayer.seekTo(`${this.currentTime + 10000}`);
        },
        onSeekBackward: async () => {
          if (this.isPlaying) {
            this.isBuffering = true;
          }
          this.ijkPlayer.seekTo(`${Math.max(0, this.currentTime - 10000)}`);
        },
        onSpeedChange: async () => {
          const speeds = [PlaybackSpeed.SPEED_0_5, PlaybackSpeed.SPEED_1_0, PlaybackSpeed.SPEED_1_5, PlaybackSpeed.SPEED_2_0];
          const currentIdx = speeds.indexOf(this.currentSpeed);
          const nextSpeed = speeds[(currentIdx + 1) % speeds.length];
          this.currentSpeed = nextSpeed;
          this.ijkPlayer.setSpeed(`${nextSpeed}f`);
        },
        onToggleMute: async () => {
          this.isMuted = !this.isMuted;
          this.ijkPlayer.setVolume(this.isMuted ? '0' : '1.0', this.isMuted ? '0' : '1.0');
        },
        onPrevious: () => this.onPrevious(),
        onNext: () => this.onNext(),
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

        Text(this.currentError?.title || 'Playback failed')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 24, bottom: 16 })

      Row() {
        Text(`Error code: ${this.currentError?.code || 0}`)
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
        Text(this.currentError?.message || 'Unknown playback error.')
          .fontSize(15)
          .fontColor('#555555')
          .textAlign(TextAlign.Center)
          .padding({ top: 16 })
      }
      .padding({ bottom: 20 })

      Divider().color('#F0F0F0').height(1)

      Row({ space: 0 }) {
        Button('Close')
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

          Button('Retry')
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
