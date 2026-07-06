import { preferences } from '@kit.ArkData';
import { Constants } from '../common/Constants';
import { PlaybackSpeed, ScreenOrientation } from '../common/Enums';

const KEY_SHOW_SUBTITLE: string = 'show_subtitle';
const KEY_AUTO_PLAY_NEXT: string = 'auto_play_next';
const KEY_HW_ACCELERATION: string = 'hw_acceleration';
const KEY_BACKGROUND_PLAY: string = 'background_play';
const KEY_WIFI_ONLY: string = 'wifi_only';
const KEY_ORIENTATION: string = 'orientation';
const KEY_DEFAULT_SPEED: string = 'default_speed';

export class SettingsService {
  private static instance: SettingsService | null = null;
  private prefs: preferences.Preferences | null = null;

  static getInstance(): SettingsService {
    if (SettingsService.instance === null) {
      SettingsService.instance = new SettingsService();
    }
    return SettingsService.instance;
  }

  private async getPrefs(): Promise<preferences.Preferences> {
    if (!this.prefs) {
      this.prefs = await preferences.getPreferences(getContext(this), Constants.PREFS_SETTINGS);
    }
    return this.prefs;
  }

  // ==================== 字幕 ====================

  async getShowSubtitle(): Promise<boolean> {
    const prefs = await this.getPrefs();
    return (await prefs.get(KEY_SHOW_SUBTITLE, true)) as boolean;
  }

  async setShowSubtitle(value: boolean): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_SHOW_SUBTITLE, value);
    await prefs.flush();
  }

  // ==================== 播放 ====================

  async getAutoPlayNext(): Promise<boolean> {
    const prefs = await this.getPrefs();
    return (await prefs.get(KEY_AUTO_PLAY_NEXT, true)) as boolean;
  }

  async setAutoPlayNext(value: boolean): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_AUTO_PLAY_NEXT, value);
    await prefs.flush();
  }

  async getHwAcceleration(): Promise<boolean> {
    const prefs = await this.getPrefs();
    return (await prefs.get(KEY_HW_ACCELERATION, true)) as boolean;
  }

  async setHwAcceleration(value: boolean): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_HW_ACCELERATION, value);
    await prefs.flush();
  }

  async getBackgroundPlay(): Promise<boolean> {
    const prefs = await this.getPrefs();
    return (await prefs.get(KEY_BACKGROUND_PLAY, false)) as boolean;
  }

  async setBackgroundPlay(value: boolean): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_BACKGROUND_PLAY, value);
    await prefs.flush();
  }

  async getDefaultSpeed(): Promise<PlaybackSpeed> {
    const prefs = await this.getPrefs();
    const val = await prefs.get(KEY_DEFAULT_SPEED, PlaybackSpeed.SPEED_1_0) as number;
    // Validate against known speeds (explicit check for ArkTS compatibility)
    if (val === PlaybackSpeed.SPEED_0_5 || val === PlaybackSpeed.SPEED_0_75 ||
        val === PlaybackSpeed.SPEED_1_0 || val === PlaybackSpeed.SPEED_1_25 ||
        val === PlaybackSpeed.SPEED_1_5 || val === PlaybackSpeed.SPEED_2_0) {
      return val as PlaybackSpeed;
    }
    return PlaybackSpeed.SPEED_1_0;
  }

  async setDefaultSpeed(value: PlaybackSpeed): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_DEFAULT_SPEED, value);
    await prefs.flush();
  }

  // ==================== 显示 ====================

  async getOrientation(): Promise<ScreenOrientation> {
    const prefs = await this.getPrefs();
    const val = await prefs.get(KEY_ORIENTATION, ScreenOrientation.AUTO) as string;
    if (val === ScreenOrientation.LANDSCAPE || val === ScreenOrientation.PORTRAIT || val === ScreenOrientation.AUTO) {
      return val as ScreenOrientation;
    }
    return ScreenOrientation.AUTO;
  }

  async setOrientation(value: ScreenOrientation): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_ORIENTATION, value);
    await prefs.flush();
  }

  // ==================== 网络 ====================

  async getWifiOnly(): Promise<boolean> {
    const prefs = await this.getPrefs();
    return (await prefs.get(KEY_WIFI_ONLY, true)) as boolean;
  }

  async setWifiOnly(value: boolean): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_WIFI_ONLY, value);
    await prefs.flush();
  }
}
