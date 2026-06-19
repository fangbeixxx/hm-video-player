import { router } from '@kit.ArkUI';
import { PlayHistoryService } from '../service/PlayHistoryService';
import { PlaybackSpeed, ScreenOrientation } from '../common/Enums';

@Entry
@Component
struct SettingsPage {
  @State defaultSpeed: PlaybackSpeed = PlaybackSpeed.SPEED_1_0;
  @State autoPlayNext: boolean = true;
  @State hwAcceleration: boolean = true;
  @State backgroundPlay: boolean = false;
  @State orientation: ScreenOrientation = ScreenOrientation.AUTO;
  @State showSubtitle: boolean = true;
  @State wifiOnly: boolean = true;
  @State historyCount: number = 0;

  private historyService: PlayHistoryService = PlayHistoryService.getInstance();

  async aboutToAppear(): Promise<void> {
    try {
      const history = await this.historyService.getHistory();
      this.historyCount = history.length;
    } catch (error) {
      console.error('Load settings failed.');
    }
  }

  private async clearHistory(): Promise<void> {
    await this.historyService.clearHistory();
    this.historyCount = 0;
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor('#333333')
          .onClick(() => router.back())

        Text('Settings')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      List({ space: 0 }) {
        ListItem() {
          this.SectionHeader('Playback')
        }

        ListItem() {
          this.SwitchItem('Auto play next', this.autoPlayNext, (val: boolean) => {
            this.autoPlayNext = val;
          })
        }

        ListItem() {
          this.SwitchItem('Hardware acceleration', this.hwAcceleration, (val: boolean) => {
            this.hwAcceleration = val;
          })
        }

        ListItem() {
          this.SwitchItem('Background play', this.backgroundPlay, (val: boolean) => {
            this.backgroundPlay = val;
          })
        }

        ListItem() {
          this.SelectItem('Default speed', this.getSpeedLabel(this.defaultSpeed), () => {
            this.cycleSpeed();
          })
        }

        ListItem() {
          this.SectionHeader('Display')
        }

        ListItem() {
          this.SelectItem('Orientation', this.getOrientationLabel(this.orientation), () => {
            this.cycleOrientation();
          })
        }

        ListItem() {
          this.SwitchItem('Show subtitles', this.showSubtitle, (val: boolean) => {
            this.showSubtitle = val;
          })
        }

        ListItem() {
          this.SectionHeader('Network')
        }

        ListItem() {
          this.SwitchItem('Wi-Fi only', this.wifiOnly, (val: boolean) => {
            this.wifiOnly = val;
          })
        }

        ListItem() {
          this.SectionHeader('Data')
        }

        ListItem() {
          Row() {
            Text('Playback history')
              .fontSize(15)
              .fontColor('#333333')
              .layoutWeight(1)

            Text(`${this.historyCount} records`)
              .fontSize(13)
              .fontColor('#999999')

            Text('Clear')
              .fontSize(14)
              .fontColor('#FF4081')
              .margin({ left: 12 })
              .onClick(() => this.clearHistory())
          }
          .width('100%')
          .height(52)
          .padding({ left: 24, right: 16 })
          .backgroundColor('#FFFFFF')
        }

        ListItem() {
          this.SectionHeader('About')
        }

        ListItem() {
          Row() {
            Text('Version')
              .fontSize(15)
              .fontColor('#333333')
              .layoutWeight(1)

            Text('v1.0.0')
              .fontSize(13)
              .fontColor('#999999')
          }
          .width('100%')
          .height(52)
          .padding({ left: 24, right: 16 })
          .backgroundColor('#FFFFFF')
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ color: '#F0F0F0', strokeWidth: 1 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  SectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#999999')
      .padding({ left: 24, top: 20, bottom: 8 })
      .width('100%')
      .backgroundColor('#F5F5F5')
  }

  @Builder
  SwitchItem(title: string, value: boolean, onChange: (val: boolean) => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor('#333333')
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: value })
        .onChange((isOn: boolean) => onChange(isOn))
    }
    .width('100%')
    .height(52)
    .padding({ left: 24, right: 16 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  SelectItem(title: string, value: string, onClick: () => void) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontColor('#333333')
        .layoutWeight(1)

      Text(value)
        .fontSize(13)
        .fontColor('#999999')

      Image($r('app.media.ic_arrow_right'))
        .width(16)
        .height(16)
        .fillColor('#CCCCCC')
        .margin({ left: 4 })
    }
    .width('100%')
    .height(52)
    .padding({ left: 24, right: 16 })
    .backgroundColor('#FFFFFF')
    .onClick(() => onClick())
  }

  private getSpeedLabel(speed: PlaybackSpeed): string {
    switch (speed) {
      case PlaybackSpeed.SPEED_0_5:
        return '0.5x';
      case PlaybackSpeed.SPEED_0_75:
        return '0.75x';
      case PlaybackSpeed.SPEED_1_25:
        return '1.25x';
      case PlaybackSpeed.SPEED_1_5:
        return '1.5x';
      case PlaybackSpeed.SPEED_2_0:
        return '2.0x';
      default:
        return '1.0x';
    }
  }

  private cycleSpeed(): void {
    const speeds: PlaybackSpeed[] = [
      PlaybackSpeed.SPEED_0_5,
      PlaybackSpeed.SPEED_0_75,
      PlaybackSpeed.SPEED_1_0,
      PlaybackSpeed.SPEED_1_25,
      PlaybackSpeed.SPEED_1_5,
      PlaybackSpeed.SPEED_2_0
    ];
    const idx = speeds.indexOf(this.defaultSpeed);
    this.defaultSpeed = speeds[(idx + 1) % speeds.length];
  }

  private getOrientationLabel(orientation: ScreenOrientation): string {
    switch (orientation) {
      case ScreenOrientation.LANDSCAPE:
        return 'Landscape';
      case ScreenOrientation.PORTRAIT:
        return 'Portrait';
      default:
        return 'Auto';
    }
  }

  private cycleOrientation(): void {
    const orientations: ScreenOrientation[] = [
      ScreenOrientation.AUTO,
      ScreenOrientation.LANDSCAPE,
      ScreenOrientation.PORTRAIT
    ];
    const idx = orientations.indexOf(this.orientation);
    this.orientation = orientations[(idx + 1) % orientations.length];
  }
}
