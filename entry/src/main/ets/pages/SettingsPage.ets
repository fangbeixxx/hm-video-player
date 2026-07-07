import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { PlayHistoryService } from '../service/PlayHistoryService';
import { SettingsService } from '../service/SettingsService';
import { PlaybackSpeed, ScreenOrientation, AppLanguage } from '../common/Enums';
import { LocalizationManager } from '../utils/LocalizationManager';

interface SpeedOption { label: string; value: PlaybackSpeed; }
interface OrientOption { label: string; value: ScreenOrientation; }
interface LangOption { label: string; value: AppLanguage; }

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
  @State safeAreaTop: number = 0;

  // Option dialogs
  @State showSpeedDialog: boolean = false;
  @State showOrientationDialog: boolean = false;
  @State showLanguageDialog: boolean = false;

  @StorageLink('appLanguage') appLanguage: AppLanguage = AppLanguage.SYSTEM;
  @State languageLabel: string = 'System';
  private historyService: PlayHistoryService = PlayHistoryService.getInstance();
  private settingsService: SettingsService = SettingsService.getInstance();
  private loc: LocalizationManager = LocalizationManager.getInstance();

  async aboutToAppear(): Promise<void> {
    await this.initSafeArea();
    await this.loadSettings();
    // Load persisted language
    try {
      const savedLang: AppLanguage = await this.settingsService.getLanguage();
      this.loc.setLanguage(savedLang);
      AppStorage.set('appLanguage', savedLang);
      this.languageLabel = this.loc.getLanguageLabel();
    } catch (e) {
      // use default SYSTEM
    }
    try {
      const history = await this.historyService.getHistory();
      this.historyCount = history.length;
    } catch (error) {
      console.error('Load settings failed.');
    }
  }

  private async loadSettings(): Promise<void> {
    this.showSubtitle = await this.settingsService.getShowSubtitle();
    this.autoPlayNext = await this.settingsService.getAutoPlayNext();
    this.hwAcceleration = await this.settingsService.getHwAcceleration();
    this.backgroundPlay = await this.settingsService.getBackgroundPlay();
    this.wifiOnly = await this.settingsService.getWifiOnly();
    this.orientation = await this.settingsService.getOrientation();
    this.defaultSpeed = await this.settingsService.getDefaultSpeed();
  }

  private async initSafeArea(): Promise<void> {
    try {
      const windowStage = window.getLastWindow(getContext(this));
      const mainWindow = await windowStage;
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.safeAreaTop = px2vp(area.topRect.height);
    } catch (e) {
      console.error('Get safe area failed:', e);
      this.safeAreaTop = 0;
    }
  }

  private async clearHistory(): Promise<void> {
    await this.historyService.clearHistory();
    this.historyCount = 0;
  }

  build() {
    Stack() {
      Column() {
      Column()
        .width('100%')
        .height(this.safeAreaTop)
        .backgroundColor('#FFFFFF')

      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor('#333333')
          .onClick(() => router.back())

        Text(this.loc.getString('settings_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      List({ space: 0 }) {
        ListItem() {
          this.SectionHeader(this.loc.getString('settings_playback'))
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_auto_play_next'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoPlayNext })
              .onChange(async (isOn: boolean) => {
                this.autoPlayNext = isOn;
                await this.settingsService.setAutoPlayNext(isOn);
              })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_hw_accel'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.hwAcceleration })
              .onChange(async (isOn: boolean) => {
                this.hwAcceleration = isOn;
                await this.settingsService.setHwAcceleration(isOn);
              })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_background_play'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.backgroundPlay })
              .onChange(async (isOn: boolean) => {
                this.backgroundPlay = isOn;
                await this.settingsService.setBackgroundPlay(isOn);
              })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_default_speed'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Text(this.getSpeedLabel(this.defaultSpeed)).fontSize(13).fontColor('#999999')
            Image($r('app.media.ic_arrow_right')).width(16).height(16).fillColor('#CCCCCC').margin({ left: 4 })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
          .onClick(() => { this.showSpeedDialog = true; })
        }

        ListItem() {
          this.SectionHeader(this.loc.getString('settings_display'))
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_orientation'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Text(this.getOrientationLabel(this.orientation)).fontSize(13).fontColor('#999999')
            Image($r('app.media.ic_arrow_right')).width(16).height(16).fillColor('#CCCCCC').margin({ left: 4 })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
          .onClick(() => { this.showOrientationDialog = true; })
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_language'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Text(this.languageLabel).fontSize(13).fontColor('#999999')
            Image($r('app.media.ic_arrow_right')).width(16).height(16).fillColor('#CCCCCC').margin({ left: 4 })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
          .onClick(() => { this.showLanguageDialog = true; })
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_show_subtitles'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.showSubtitle })
              .onChange(async (isOn: boolean) => {
                this.showSubtitle = isOn;
                await this.settingsService.setShowSubtitle(isOn);
              })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
        }

        ListItem() {
          this.SectionHeader(this.loc.getString('settings_network'))
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_wifi_only'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.wifiOnly })
              .onChange(async (isOn: boolean) => {
                this.wifiOnly = isOn;
                await this.settingsService.setWifiOnly(isOn);
              })
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
        }

        ListItem() {
          this.SectionHeader(this.loc.getString('settings_data'))
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_history'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Text(`${this.historyCount} ${this.loc.getString('settings_records')}`)
              .fontSize(13).fontColor('#999999')
            Text(this.loc.getString('settings_clear'))
              .fontSize(14).fontColor('#FF4081').margin({ left: 12 })
              .onClick(() => this.clearHistory())
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
        }

        ListItem() {
          this.SectionHeader(this.loc.getString('settings_about'))
        }

        ListItem() {
          Row() {
            Text(this.loc.getString('settings_version'))
              .fontSize(15).fontColor('#333333').layoutWeight(1)
            Text('v1.0.0').fontSize(13).fontColor('#999999')
          }
          .width('100%').height(52).padding({ left: 24, right: 16 }).backgroundColor('#FFFFFF')
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ color: '#F0F0F0', strokeWidth: 1 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')

    // ═══ Speed Dialog ═══
    if (this.showSpeedDialog) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.showSpeedDialog = false; })
        Column() {
          Text(this.loc.getString('settings_default_speed'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
            .padding({ left: 20, right: 20, top: 16, bottom: 12 })
          List({ space: 0 }) {
            ForEach(this.getSpeedOptions(), (opt: SpeedOption) => {
              ListItem() {
                Row() {
                  Text(opt.label).fontSize(15).fontColor('#333333').layoutWeight(1)
                  if (opt.value === this.defaultSpeed) {
                    Text('✓').fontSize(16).fontColor('#FF4081')
                  }
                }
                .width('100%').height(48).padding({ left: 20, right: 20 })
                .onClick(() => { this.defaultSpeed = opt.value; this.settingsService.setDefaultSpeed(opt.value); this.showSpeedDialog = false; })
              }
            })
          }
          .divider({ color: '#F0F0F0', strokeWidth: 0.5 })
        }
        .width('80%').backgroundColor('#FFFFFF').borderRadius(12)
      }
      .width('100%').height('100%').position({ x: 0, y: 0 })
    }

    // ═══ Orientation Dialog ═══
    if (this.showOrientationDialog) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.showOrientationDialog = false; })
        Column() {
          Text(this.loc.getString('settings_orientation'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
            .padding({ left: 20, right: 20, top: 16, bottom: 12 })
          List({ space: 0 }) {
            ForEach(this.getOrientationOptions(), (opt: OrientOption) => {
              ListItem() {
                Row() {
                  Text(opt.label).fontSize(15).fontColor('#333333').layoutWeight(1)
                  if (opt.value === this.orientation) {
                    Text('✓').fontSize(16).fontColor('#FF4081')
                  }
                }
                .width('100%').height(48).padding({ left: 20, right: 20 })
                .onClick(() => { this.orientation = opt.value; this.settingsService.setOrientation(opt.value); this.showOrientationDialog = false; })
              }
            })
          }
          .divider({ color: '#F0F0F0', strokeWidth: 0.5 })
        }
        .width('80%').backgroundColor('#FFFFFF').borderRadius(12)
      }
      .width('100%').height('100%').position({ x: 0, y: 0 })
    }

    // ═══ Language Dialog ═══
    if (this.showLanguageDialog) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.showLanguageDialog = false; })
        Column() {
          Text(this.loc.getString('settings_language'))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
            .padding({ left: 20, right: 20, top: 16, bottom: 12 })
          List({ space: 0 }) {
            ForEach(this.getLanguageOptions(), (opt: LangOption) => {
              ListItem() {
                Row() {
                  Text(opt.label).fontSize(15).fontColor('#333333').layoutWeight(1)
                  if (opt.value === this.loc.getLanguage()) {
                    Text('✓').fontSize(16).fontColor('#FF4081')
                  }
                }
                .width('100%').height(48).padding({ left: 20, right: 20 })
                .onClick(() => { this.loc.setLanguage(opt.value); AppStorage.set('appLanguage', opt.value); this.settingsService.setLanguage(opt.value); this.languageLabel = this.loc.getLanguageLabel(); this.showLanguageDialog = false; })
              }
            })
          }
          .divider({ color: '#F0F0F0', strokeWidth: 0.5 })
        }
        .width('80%').backgroundColor('#FFFFFF').borderRadius(12)
      }
      .width('100%').height('100%').position({ x: 0, y: 0 })
    }
    }
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
      case PlaybackSpeed.SPEED_0_5: return '0.5x';
      case PlaybackSpeed.SPEED_0_75: return '0.75x';
      case PlaybackSpeed.SPEED_1_25: return '1.25x';
      case PlaybackSpeed.SPEED_1_5: return '1.5x';
      case PlaybackSpeed.SPEED_2_0: return '2.0x';
      default: return '1.0x';
    }
  }

  private getOrientationLabel(orientation: ScreenOrientation): string {
    switch (orientation) {
      case ScreenOrientation.LANDSCAPE: return this.loc.getString('orient_landscape');
      case ScreenOrientation.PORTRAIT: return this.loc.getString('orient_portrait');
      default: return this.loc.getString('orient_auto');
    }
  }

  // ─── Option dialog data ───

  private getSpeedOptions(): SpeedOption[] {
    const opts: SpeedOption[] = [];
    opts.push({ label: '0.5x', value: PlaybackSpeed.SPEED_0_5 });
    opts.push({ label: '0.75x', value: PlaybackSpeed.SPEED_0_75 });
    opts.push({ label: '1.0x', value: PlaybackSpeed.SPEED_1_0 });
    opts.push({ label: '1.25x', value: PlaybackSpeed.SPEED_1_25 });
    opts.push({ label: '1.5x', value: PlaybackSpeed.SPEED_1_5 });
    opts.push({ label: '2.0x', value: PlaybackSpeed.SPEED_2_0 });
    return opts;
  }

  private getOrientationOptions(): OrientOption[] {
    const opts: OrientOption[] = [];
    opts.push({ label: this.loc.getString('orient_auto'), value: ScreenOrientation.AUTO });
    opts.push({ label: this.loc.getString('orient_landscape'), value: ScreenOrientation.LANDSCAPE });
    opts.push({ label: this.loc.getString('orient_portrait'), value: ScreenOrientation.PORTRAIT });
    return opts;
  }

  private getLanguageOptions(): LangOption[] {
    const opts: LangOption[] = [];
    opts.push({ label: this.loc.getString('lang_system'), value: AppLanguage.SYSTEM });
    opts.push({ label: this.loc.getString('lang_zh'), value: AppLanguage.ZH_CN });
    opts.push({ label: this.loc.getString('lang_en'), value: AppLanguage.EN_US });
    return opts;
  }
}
