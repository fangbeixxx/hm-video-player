import { VideoPlayerManager } from '../service/VideoPlayerManager';
import { ControlPanel } from './ControlPanel';
import { ErrorToast } from './ErrorDialog';
import { PlayerState, PlaybackSpeed } from '../common/Enums';
import { PlayerError, PlayerErrorCode, createPlayerError } from '../common/PlayerError';
import { PlayHistoryService } from '../service/PlayHistoryService';

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
  @State engineType: string = '';

  private saveTimerId: number = -1;

  async aboutToAppear(): Promise<void> {
    await this.playerManager.init({
      onStateChange: (state: PlayerState) => {
        this.playerState = state;
        this.isPlaying = state === PlayerState.PLAYING;
      },
      onTimeUpdate: (timeMs: number) => {
        this.currentTime = timeMs;
        if (this.saveTimerId < 0) {
          this.saveTimerId = setInterval(() => {
            this.saveProgress();
          }, 5000);
        }
      },
      onDurationUpdate: (dur: number) => {
        this.duration = dur;
      },
      onBufferingUpdate: (buffering: boolean) => {
        this.isBuffering = buffering;
      },
      onError: (error: PlayerError) => {
        this.handleError(error);
      },
      onCompleted: () => {
        this.saveProgress();
      }
    });

    try {
      if (this.videoPath.startsWith('http')) {
        await this.playerManager.setUrlSource(this.videoPath);
      } else {
        await this.playerManager.setSource(this.videoPath);
      }
      this.engineType = this.playerManager.engineType;
      await this.playerManager.play();
    } catch (error) {
      const playerError = createPlayerError(PlayerErrorCode.UNKNOWN, 'Unable to start playback.');
      this.handleError(playerError);
    }
  }

  async aboutToDisappear(): Promise<void> {
    if (this.saveTimerId >= 0) {
      clearInterval(this.saveTimerId);
      this.saveTimerId = -1;
    }
    await this.saveProgress();
    await this.playerManager.release();
  }

  private handleError(error: PlayerError): void {
    console.error(`Playback error [${error.code}]: ${error.message}`);

    if (error.code === PlayerErrorCode.FILE_NO_AUDIO_STREAM ||
        error.code === PlayerErrorCode.AUDIO_OUTPUT_ERROR) {
      this.toastMessage = error.message;
      this.showErrorToast = true;
      setTimeout(() => {
        this.showErrorToast = false;
      }, 5000);
      return;
    }

    this.currentError = error;
    this.showErrorDialog = true;
  }

  private async retryPlay(): Promise<void> {
    this.currentError = null;
    this.showErrorDialog = false;

    try {
      await this.playerManager.release();
      await this.playerManager.init();

      if (this.videoPath.startsWith('http')) {
        await this.playerManager.setUrlSource(this.videoPath);
      } else {
        await this.playerManager.setSource(this.videoPath);
      }
      this.engineType = this.playerManager.engineType;
      await this.playerManager.play();
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
      Video({
        src: this.videoPath
      })
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .onStart(() => {
          this.isPlaying = true;
        })
        .onPause(() => {
          this.isPlaying = false;
        })
        .onFinish(() => {
          this.isPlaying = false;
        })
        .onError(() => {
          this.isPlaying = false;
          if (this.currentError === null) {
            this.handleError(createPlayerError(PlayerErrorCode.DECODE_ERROR, 'System video component reported an error.'));
          }
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
          await this.playerManager.togglePlayPause();
        },
        onSeek: async (timeMs: number) => {
          await this.playerManager.seekTo(timeMs);
        },
        onSeekForward: async () => {
          await this.playerManager.seekForward();
        },
        onSeekBackward: async () => {
          await this.playerManager.seekBackward();
        },
        onSpeedChange: async () => {
          await this.playerManager.cycleSpeed();
          this.currentSpeed = this.playerManager.speed;
        },
        onToggleMute: async () => {
          await this.playerManager.toggleMute();
          this.isMuted = this.playerManager.isMuted;
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
    .backgroundColor('#000000')
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
            .fontColor('#FF9800')
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

        if (this.currentError?.suggestion) {
          Text(this.currentError?.suggestion || '')
            .fontSize(13)
            .fontColor('#888888')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24, top: 8 })
        }

        if (this.currentError?.detail) {
          Text(this.currentError?.detail || '')
            .fontSize(11)
            .fontColor('#AAAAAA')
            .fontFamily('monospace')
            .padding(12)
            .width('100%')
            .backgroundColor('#FAFAFA')
            .borderRadius(8)
            .margin({ left: 24, right: 24, top: 8 })
            .copyOption(CopyOptions.LocalDevice)
        }
      }
      .padding({ bottom: 20 })

      Divider().color('#F0F0F0').height(1)

      Row({ space: 0 }) {
        Button('Close')
          .fontSize(15)
          .fontColor('#999999')
          .backgroundColor('#FFFFFF')
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
            .backgroundColor('#FFFFFF')
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
