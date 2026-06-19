import { TimeUtils } from '../utils/TimeUtils';
import { PlayerState, PlaybackSpeed } from '../common/Enums';

/**
 * 视频控制面板组件
 */
@Component
export struct ControlPanel {
  @Prop currentTime: number;
  @Prop duration: number;
  @Prop isPlaying: boolean;
  @Prop playerState: PlayerState;
  @Prop currentSpeed: PlaybackSpeed;
  @Prop isMuted: boolean;
  @Prop isBuffering: boolean;

  onPlayPause: () => void = () => {};
  onSeek: (timeMs: number) => void = () => {};
  onSeekForward: () => void = () => {};
  onSeekBackward: () => void = () => {};
  onSpeedChange: () => void = () => {};
  onFullscreen: () => void = () => {};
  onToggleMute: () => void = () => {};
  onPrevious: () => void = () => {};
  onNext: () => void = () => {};

  @State showControls: boolean = true;
  @State isDragging: boolean = false;
  @State dragProgress: number = 0;
  @State controlTimer: number = -1;

  private timerId: number = -1;

  aboutToDisappear(): void {
    this.clearTimer();
  }

  /**
   * 显示控制栏并设置自动隐藏
   */
  private showAndAutoHide(): void {
    this.showControls = true;
    this.clearTimer();
    this.timerId = setTimeout(() => {
      this.showControls = false;
    }, 5000);
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 缓冲指示器
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

      // 控制层
      if (this.showControls) {
        Column() {
          // 顶部栏
          Row() {
            Blank()
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              Image($r('app.media.ic_more'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
            }
            .width(40)
            .height(40)
            .backgroundColor('transparent')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })

          Blank()

          // 底部控制栏
          Column({ space: 8 }) {
            // 进度条
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
                    this.showAndAutoHide();
                  }
                })

              Text(TimeUtils.formatTime(this.duration))
                .fontSize(12)
                .fontColor('#CCFFFFFF')
                .width(50)
            }
            .width('100%')
            .padding({ left: 12, right: 12 })

            // 按钮栏
            Row() {
              // 播放速度
              Text(`${this.currentSpeed}x`)
                .fontSize(14)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .borderRadius(4)
                .backgroundColor('rgba(255,255,255,0.15)')
                .onClick(() => this.onSpeedChange())

              Blank()

              // 上一集
              Image($r('app.media.ic_skip_previous'))
                .width(32)
                .height(32)
                .fillColor('#FFFFFF')
                .onClick(() => this.onPrevious())

              // 快退
              Image($r('app.media.ic_replay_10'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
                .margin({ left: 16, right: 16 })
                .onClick(() => this.onSeekBackward())

              // 播放/暂停
              Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
                .width(52)
                .height(52)
                .fillColor('#FFFFFF')
                .onClick(() => this.onPlayPause())

              // 快进
              Image($r('app.media.ic_forward_10'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
                .margin({ left: 16, right: 16 })
                .onClick(() => this.onSeekForward())

              // 下一集
              Image($r('app.media.ic_skip_next'))
                .width(32)
                .height(32)
                .fillColor('#FFFFFF')
                .onClick(() => this.onNext())

              Blank()

              // 静音
              Image(this.isMuted ? $r('app.media.ic_volume_off') : $r('app.media.ic_volume_on'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
                .onClick(() => this.onToggleMute())

              // 全屏
              Image($r('app.media.ic_fullscreen'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
                .margin({ left: 16 })
                .onClick(() => this.onFullscreen())
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.35)')
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.isDragging) return;
      if (this.showControls) {
        this.showControls = false;
        this.clearTimer();
      } else {
        this.showAndAutoHide();
      }
    })
  }
}
