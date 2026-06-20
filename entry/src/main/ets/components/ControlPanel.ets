import { TimeUtils } from '../utils/TimeUtils';
import { PlayerState, PlaybackSpeed } from '../common/Enums';

@Component
export struct ControlPanel {
  @Prop currentTime: number;
  @Prop duration: number;
  @Prop isPlaying: boolean;
  @Prop playerState: PlayerState;
  @Prop currentSpeed: PlaybackSpeed;
  @Prop isMuted: boolean;
  @Prop isBuffering: boolean;
  @Prop title: string = '';

  onPlayPause: () => void = () => {};
  onSeek: (timeMs: number) => void = () => {};
  onSeekForward: () => void = () => {};
  onSeekBackward: () => void = () => {};
  onSpeedChange: () => void = () => {};
  onFullscreen: () => void = () => {};
  onToggleMute: () => void = () => {};
  onPrevious: () => void = () => {};
  onNext: () => void = () => {};
  onBack: () => void = () => {};

  @State showControls: boolean = true;
  @State isDragging: boolean = false;
  @State dragProgress: number = 0;

  private timerId: number = -1;
  private autoHidePollId: number = -1;
  private lastAutoHideSignature: string = '';

  aboutToAppear(): void {
    this.syncAutoHideState();
    this.startAutoHidePolling();
  }

  aboutToDisappear(): void {
    this.clearTimer();
    this.stopAutoHidePolling();
  }

  private startAutoHidePolling(): void {
    this.stopAutoHidePolling();
    this.lastAutoHideSignature = this.buildAutoHideSignature();
    this.autoHidePollId = setInterval(() => {
      const nextSignature = this.buildAutoHideSignature();
      if (nextSignature !== this.lastAutoHideSignature) {
        this.lastAutoHideSignature = nextSignature;
        this.syncAutoHideState();
      }
    }, 250);
  }

  private stopAutoHidePolling(): void {
    if (this.autoHidePollId >= 0) {
      clearInterval(this.autoHidePollId);
      this.autoHidePollId = -1;
    }
  }

  private buildAutoHideSignature(): string {
    return `${this.isPlaying}|${this.playerState}|${this.isBuffering}|${this.isDragging}`;
  }

  private syncAutoHideState(): void {
    if (this.isDragging || this.isBuffering || this.playerState === PlayerState.PAUSED || !this.isPlaying) {
      this.showControls = true;
      this.clearTimer();
      return;
    }
    this.showAndAutoHide();
  }

  private showAndAutoHide(): void {
    this.showControls = true;
    this.clearTimer();
    if (!this.isPlaying || this.isBuffering || this.playerState === PlayerState.PAUSED) {
      return;
    }
    this.timerId = setTimeout(() => {
      this.showControls = false;
    }, 3200);
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isBuffering) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      if (this.showControls) {
        Column() {
          Row({ space: 12 }) {
            Image($r('app.media.ic_arrow_back'))
              .width(22)
              .height(22)
              .fillColor('#FFFFFF')
              .padding(8)
              .backgroundColor('rgba(255,255,255,0.08)')
              .borderRadius(20)
              .onClick(() => this.onBack())

            Text(this.title)
              .fontSize(16)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Button({ type: ButtonType.Circle, stateEffect: true }) {
              Image($r('app.media.ic_more'))
                .width(20)
                .height(20)
                .fillColor('#FFFFFF')
            }
            .width(36)
            .height(36)
            .backgroundColor('rgba(255,255,255,0.08)')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })

          Blank()

          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text(TimeUtils.formatTime(this.isDragging ? this.dragProgress : this.currentTime))
                .fontSize(12)
                .fontColor('#CCFFFFFF')
                .width(50)
                .textAlign(TextAlign.End)

              Slider({
                value: this.isDragging ? this.dragProgress : this.currentTime,
                min: 0,
                max: this.duration > 0 ? this.duration : 1,
                step: 1000
              })
                .blockColor('#FFFFFF')
                .trackColor('#66FFFFFF')
                .selectedColor('#FF4081')
                .layoutWeight(1)
                .onChange((value: number) => {
                  if (this.isDragging) {
                    this.dragProgress = value;
                  }
                })
                .onTouch((event: TouchEvent) => {
                  if (event.type === TouchType.Down) {
                    this.isDragging = true;
                    this.dragProgress = this.currentTime;
                    this.clearTimer();
                  } else if (event.type === TouchType.Up) {
                    this.isDragging = false;
                    this.onSeek(this.dragProgress);
                    this.syncAutoHideState();
                  }
                })

              Text(TimeUtils.formatTime(this.duration))
                .fontSize(12)
                .fontColor('#CCFFFFFF')
                .width(50)
            }
            .width('100%')
            .padding({ left: 12, right: 12 })

            Row() {
              Text(`${this.currentSpeed}x`)
                .fontSize(14)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .borderRadius(4)
                .backgroundColor('rgba(255,255,255,0.15)')
                .onClick(() => {
                  this.onSpeedChange();
                  this.showAndAutoHide();
                })

              Blank()

              Image($r('app.media.ic_skip_previous'))
                .width(32)
                .height(32)
                .fillColor('#FFFFFF')
                .onClick(() => {
                  this.onPrevious();
                  this.showAndAutoHide();
                })

              Image($r('app.media.ic_replay_10'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
                .margin({ left: 16, right: 16 })
                .onClick(() => {
                  this.onSeekBackward();
                  this.showAndAutoHide();
                })

              Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
                .width(52)
                .height(52)
                .fillColor('#FFFFFF')
                .onClick(() => {
                  this.onPlayPause();
                  this.syncAutoHideState();
                })

              Image($r('app.media.ic_forward_10'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
                .margin({ left: 16, right: 16 })
                .onClick(() => {
                  this.onSeekForward();
                  this.showAndAutoHide();
                })

              Image($r('app.media.ic_skip_next'))
                .width(32)
                .height(32)
                .fillColor('#FFFFFF')
                .onClick(() => {
                  this.onNext();
                  this.showAndAutoHide();
                })

              Blank()

              Image(this.isMuted ? $r('app.media.ic_volume_off') : $r('app.media.ic_volume_on'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
                .onClick(() => {
                  this.onToggleMute();
                  this.showAndAutoHide();
                })

              Image($r('app.media.ic_fullscreen'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
                .margin({ left: 16 })
                .onClick(() => {
                  this.onFullscreen();
                  this.showAndAutoHide();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 14 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.28)')
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.isDragging) {
        return;
      }
      if (this.showControls) {
        this.showControls = false;
        this.clearTimer();
      } else {
        this.showAndAutoHide();
      }
    })
  }
}
