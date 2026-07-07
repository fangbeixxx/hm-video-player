import { TimeUtils } from '../utils/TimeUtils';
import { PlayerState, PlaybackSpeed, AppLanguage } from '../common/Enums';
import { QualityOption } from '../model/OnlineMedia';
import { LocalizationManager } from '../utils/LocalizationManager';

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

  // Gesture-related props
  @Prop panelBrightness: number = 0.5;
  @Prop volume: number = 1.0;
  @Prop subtitleDelayMs: number = 0;

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
  // Gesture callbacks
  onBrightnessChange: (brightness: number) => void = () => {};
  onVolumeChange: (volume: number) => void = () => {};
  onGestureSeek: (timeMs: number) => void = () => {};
  // Subtitle callbacks
  onSubtitleDelayChange: (delayMs: number) => void = () => {};
  onLoadSubtitle: () => void = () => {};
  // Quality callbacks
  @Prop qualities: QualityOption[] = [];
  @Prop currentQualityLabel: string = 'Auto';
  onQualityChange: (option: QualityOption) => void = () => {};
  // Danmaku
  @Prop danmakuEnabled: boolean = false;
  onToggleDanmaku: () => void = () => {};
  onSendDanmaku: (text: string) => void = () => {};
  // PiP
  @Prop isPiPActive: boolean = false;
  onTogglePiP: () => void = () => {};

  @StorageLink('appLanguage') appLanguage: AppLanguage = AppLanguage.SYSTEM;
  private loc: LocalizationManager = LocalizationManager.getInstance();

  @State showControls: boolean = true;
  @State isDragging: boolean = false;
  @State dragProgress: number = 0;
  @State showMoreMenu: boolean = false;

  // Gesture states
  @State gestureType: 'none' | 'brightness' | 'volume' | 'seek' = 'none';
  @State gestureIndicatorValue: string = '';
  @State gestureSeekTime: number = 0;
  @State gestureSeekDuration: number = 0;
  private gestureStartX: number = 0;
  private gestureStartY: number = 0;
  private gestureStartBrightness: number = 0;
  private gestureStartVolume: number = 0;
  private gestureStartTime: number = 0;
  private gestureIndicatorTimerId: number = -1;
  private readonly gestureThresholdVp: number = 10;

  private timerId: number = -1;
  private autoHidePollId: number = -1;
  private lastAutoHideSignature: string = '';
  private singleTapTimerId: number = -1;
  private lastTapTimestamp: number = 0;
  private readonly doubleTapThresholdMs: number = 280;

  aboutToAppear(): void {
    this.syncAutoHideState();
    this.startAutoHidePolling();
  }

  aboutToDisappear(): void {
    this.clearTimer();
    this.clearSingleTapTimer();
    this.stopAutoHidePolling();
    this.clearGestureIndicator();
    this.showMoreMenu = false;
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

  private clearSingleTapTimer(): void {
    if (this.singleTapTimerId >= 0) {
      clearTimeout(this.singleTapTimerId);
      this.singleTapTimerId = -1;
    }
  }

  private toggleControlsVisibility(): void {
    this.showMoreMenu = false;
    if (this.showControls) {
      this.showControls = false;
      this.clearTimer();
      return;
    }
    this.showAndAutoHide();
  }

  private handleBackgroundTap(): void {
    if (this.isDragging) {
      return;
    }
    this.showMoreMenu = false;
    const now = Date.now();
    const isDoubleTap = this.lastTapTimestamp > 0 && now - this.lastTapTimestamp <= this.doubleTapThresholdMs;
    if (isDoubleTap) {
      this.lastTapTimestamp = 0;
      this.clearSingleTapTimer();
      this.onPlayPause();
      this.syncAutoHideState();
      return;
    }
    this.lastTapTimestamp = now;
    this.clearSingleTapTimer();
    this.singleTapTimerId = setTimeout(() => {
      this.singleTapTimerId = -1;
      this.lastTapTimestamp = 0;
      this.toggleControlsVisibility();
    }, this.doubleTapThresholdMs);
  }

  // ========== Gesture Handling ==========

  private handlePanStart(event: GestureEvent): void {
    this.gestureStartX = event.offsetX;
    this.gestureStartY = event.offsetY;
    this.gestureStartBrightness = this.panelBrightness;
    this.gestureStartVolume = this.volume;
    this.gestureStartTime = this.currentTime;
    this.gestureType = 'none';
    this.clearGestureIndicator();
  }

  private handlePanUpdate(event: GestureEvent): void {
    const dx = event.offsetX - this.gestureStartX;
    const dy = event.offsetY - this.gestureStartY;
    const absDx = Math.abs(dx);
    const absDy = Math.abs(dy);

    // If gesture type not yet determined and threshold not met, wait
    if (this.gestureType === 'none') {
      if (absDx < this.gestureThresholdVp && absDy < this.gestureThresholdVp) {
        return;
      }
      // Determine gesture type
      if (absDx > absDy) {
        this.gestureType = 'seek';
      } else {
        // Left side = brightness, right side = volume
        this.gestureType = this.gestureStartX < 100 ? 'brightness' : 'volume';
      }
    }

    if (this.gestureType === 'brightness') {
      const delta = -dy / 400;
      const newBrightness = Math.max(0.01, Math.min(1.0, this.gestureStartBrightness + delta));
      this.onBrightnessChange(newBrightness);
      this.gestureIndicatorValue = `${this.loc.getString('cp_brightness')} ${Math.round(newBrightness * 100)}%`;
      this.showGestureIndicator();
    } else if (this.gestureType === 'volume') {
      const delta = -dy / 400;
      const newVolume = Math.max(0, Math.min(1.0, this.gestureStartVolume + delta));
      this.onVolumeChange(newVolume);
      this.gestureIndicatorValue = `${this.loc.getString('cp_volume')} ${Math.round(newVolume * 100)}%`;
      this.showGestureIndicator();
    } else if (this.gestureType === 'seek') {
      const delta = (dx / 300) * 30000;
      const newTime = Math.max(0, Math.min(this.duration, this.gestureStartTime + delta));
      this.gestureSeekTime = newTime;
      this.gestureSeekDuration = this.duration;
      this.gestureIndicatorValue = `${TimeUtils.formatTime(newTime)} / ${TimeUtils.formatTime(this.duration)}`;
      this.showGestureIndicator();
    }
  }

  private handlePanEnd(_event: GestureEvent): void {
    if (this.gestureType === 'seek' && this.gestureSeekTime > 0) {
      this.onGestureSeek(this.gestureSeekTime);
    }
    this.gestureType = 'none';
    this.clearGestureIndicator();
    this.syncAutoHideState();
  }

  private showGestureIndicator(): void {
    this.clearGestureIndicator();
    this.gestureIndicatorTimerId = setTimeout(() => {
      this.gestureType = 'none';
      this.gestureIndicatorValue = '';
    }, 1200);
  }

  private clearGestureIndicator(): void {
    if (this.gestureIndicatorTimerId >= 0) {
      clearTimeout(this.gestureIndicatorTimerId);
      this.gestureIndicatorTimerId = -1;
    }
  }

  // ========== Build ==========

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // Buffering indicator
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

      // Gesture indicator overlay
      if (this.gestureType !== 'none') {
        Column() {
          Blank()
          Column({ space: 12 }) {
            if (this.gestureType === 'brightness') {
              // Brightness icon
              Image($r('app.media.ic_search'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
            } else if (this.gestureType === 'volume') {
              Image(this.volume > 0 ? $r('app.media.ic_volume_on') : $r('app.media.ic_volume_off'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
            } else if (this.gestureType === 'seek') {
              Image($r('app.media.ic_forward_10'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
            }
            Text(this.gestureIndicatorValue)
              .fontSize(15)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Medium)
              .textAlign(TextAlign.Center)

            if (this.gestureType === 'brightness' || this.gestureType === 'volume') {
              Progress({
                value: this.gestureType === 'brightness' ? this.panelBrightness * 100 : this.volume * 100,
                total: 100,
                type: ProgressType.Linear
              })
                .width(120)
                .height(4)
                .color('#FF4081')
                .backgroundColor('rgba(255,255,255,0.3)')
            }
          }
          .padding(20)
          .backgroundColor('rgba(0,0,0,0.75)')
          .borderRadius(12)
          Blank()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // Main controls
      if (this.showControls) {
        Column() {
          // Top bar: back + title + more
          Row({ space: 12 }) {
            Image($r('app.media.ic_arrow_back'))
              .width(44)
              .height(44)
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
            .onClick(() => {
              this.showMoreMenu = !this.showMoreMenu;
              this.clearTimer();
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })

          // More menu dropdown
          if (this.showMoreMenu) {
            Column({ space: 0 }) {
              this.MenuItem(this.loc.getString('cp_load_subtitles'), () => {
                this.showMoreMenu = false;
                this.onLoadSubtitle();
                this.showAndAutoHide();
              })
              this.MenuItem(`${this.loc.getString('cp_sub_delay')}: ${this.subtitleDelayMs > 0 ? '+' : ''}${(this.subtitleDelayMs / 1000).toFixed(1)}s`, () => {
                const delays = [0, 500, 1000, -500, -1000];
                const idx = delays.indexOf(this.subtitleDelayMs);
                const nextDelay = delays[(idx + 1) % delays.length];
                this.onSubtitleDelayChange(nextDelay);
              })
              if (this.qualities.length > 0) {
                this.MenuItem(`${this.loc.getString('cp_quality')}: ${this.currentQualityLabel === 'Auto' ? this.loc.getString('cp_auto') : this.currentQualityLabel}`, () => {
                  // cycle through qualities + Auto
                  const labels: string[] = [this.loc.getString('cp_auto')];
                  for (const q of this.qualities) {
                    labels.push(q.label);
                  }
                  const displayLabel = this.currentQualityLabel === 'Auto' ? this.loc.getString('cp_auto') : this.currentQualityLabel;
                  const currentIdx = labels.indexOf(displayLabel);
                  const nextLabel = labels[(currentIdx + 1) % labels.length];
                  if (nextLabel === this.loc.getString('cp_auto')) {
                    // Switch back to default URL — handled by parent
                  } else {
                    const opt = this.qualities.find(q => q.label === nextLabel);
                    if (opt) {
                      this.showMoreMenu = false;
                      this.onQualityChange(opt);
                      return;
                    }
                  }
                })
              }
              this.MenuItem(`${this.loc.getString('cp_danmaku')}: ${this.danmakuEnabled ? this.loc.getString('cp_on') : this.loc.getString('cp_off')}`, () => {
                this.onToggleDanmaku();
              })
              // Danmaku quick send button
              if (this.danmakuEnabled) {
                this.MenuItem(this.loc.getString('cp_send_danmaku'), () => {
                  this.showMoreMenu = false;
                  // Send a simple pre-made danmaku for demo
                  const texts = ['666', 'Great!', 'LOL', 'Nice!', 'wow', 'Awesome'];
                  const text = texts[Math.floor(Math.random() * texts.length)];
                  this.onSendDanmaku(text);
                })
              }
            }
            .width(180)
            .backgroundColor('rgba(30,30,30,0.92)')
            .borderRadius(8)
            .padding({ top: 4, bottom: 4 })
            .position({ x: '60%', y: 56 })
          }

          Blank()

          // Bottom controls
          Column({ space: 10 }) {
            // Progress slider
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

            // Subtitle delay indicator (compact, shown when non-zero)
            if (this.subtitleDelayMs !== 0) {
              Row() {
                Text(`${this.loc.getString('cp_sub_delay')} ${this.subtitleDelayMs > 0 ? '+' : ''}${(this.subtitleDelayMs / 1000).toFixed(1)}s`)
                  .fontSize(10)
                  .fontColor('#FFD740')
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor('rgba(255,255,255,0.1)')
                  .borderRadius(4)
                Blank()
              }
              .width('100%')
              .padding({ left: 12, right: 12, bottom: 2 })
            }

            // Playback controls row
            Row() {
              // Speed button
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

              // Previous video
              Image($r('app.media.ic_skip_previous'))
                .width(28)
                .height(28)
                .fillColor('#FFFFFF')
                .margin({ right: 8 })
                .onClick(() => {
                  this.onPrevious();
                  this.showAndAutoHide();
                })

              // Rewind 10s
              Image($r('app.media.ic_replay_10'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
                .margin({ left: 16, right: 16 })
                .onClick(() => {
                  this.onSeekBackward();
                  this.showAndAutoHide();
                })

              // Play / Pause
              Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
                .width(52)
                .height(52)
                .fillColor('#FFFFFF')
                .onClick(() => {
                  this.onPlayPause();
                  this.syncAutoHideState();
                })

              // Forward 10s
              Image($r('app.media.ic_forward_10'))
                .width(36)
                .height(36)
                .fillColor('#FFFFFF')
                .margin({ left: 16, right: 16 })
                .onClick(() => {
                  this.onSeekForward();
                  this.showAndAutoHide();
                })

              // Next video
              Image($r('app.media.ic_skip_next'))
                .width(28)
                .height(28)
                .fillColor('#FFFFFF')
                .margin({ left: 8 })
                .onClick(() => {
                  this.onNext();
                  this.showAndAutoHide();
                })

              Blank()

              // Mute toggle
              Image(this.isMuted ? $r('app.media.ic_volume_off') : $r('app.media.ic_volume_on'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
                .onClick(() => {
                  this.onToggleMute();
                  this.showAndAutoHide();
                })

              // Fullscreen toggle
              Image($r('app.media.ic_fullscreen'))
                .width(24)
                .height(24)
                .fillColor('#FFFFFF')
                .margin({ left: 16 })
                .onClick(() => {
                  this.onFullscreen();
                  this.showAndAutoHide();
                })

              // PiP toggle
              Text(this.loc.getString('cp_pip'))
                .fontSize(11)
                .fontColor(this.isPiPActive ? '#FF4081' : '#FFFFFF')
                .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                .border({ width: 1, color: this.isPiPActive ? '#FF4081' : 'rgba(255,255,255,0.5)', radius: 4 })
                .margin({ left: 10 })
                .onClick(() => {
                  this.onTogglePiP();
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
      this.handleBackgroundTap();
    })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All })
        .onActionStart((event: GestureEvent) => {
          this.handlePanStart(event);
        })
        .onActionUpdate((event: GestureEvent) => {
          this.handlePanUpdate(event);
        })
        .onActionEnd((event: GestureEvent) => {
          this.handlePanEnd(event);
        })
    )
  }

  @Builder
  MenuItem(label: string, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#CCFFFFFF')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .width('100%')
    }
    .width('100%')
    .onClick(() => onClick())
  }
}
