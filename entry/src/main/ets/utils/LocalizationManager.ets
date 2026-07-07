import { i18n } from '@kit.LocalizationKit';
import { AppLanguage } from '../common/Enums';

/**
 * 应用内语言切换管理器
 *
 * 通过 Map<string,string> 查表实现运行时语言切换。
 * 配合 AppStorage('appLanguage') + @StorageLink 让所有页面即时响应。
 */
export class LocalizationManager {
  private static instance: LocalizationManager | null = null;
  private currentLang: AppLanguage = AppLanguage.SYSTEM;

  // ─── 中文映射表 ───
  private static zhMap: Map<string, string> = LocalizationManager.buildZhMap();

  // ─── 英文映射表 ───
  private static enMap: Map<string, string> = LocalizationManager.buildEnMap();

  static getInstance(): LocalizationManager {
    if (LocalizationManager.instance === null) {
      LocalizationManager.instance = new LocalizationManager();
    }
    return LocalizationManager.instance;
  }

  // ══════════════════════════════════════════════
  //  公共 API
  // ══════════════════════════════════════════════

  /**
   * 获取当前语言对应的字符串
   */
  getString(key: string): string {
    let lang: AppLanguage = this.currentLang;
    if (lang === AppLanguage.SYSTEM) {
      lang = this.detectSystemLang();
    }
    const map: Map<string, string> = (lang === AppLanguage.ZH_CN)
      ? LocalizationManager.zhMap : LocalizationManager.enMap;
    const value: string | undefined = map.get(key);
    if (value !== undefined) {
      return value;
    }
    return key; // 兜底：返回 key 本身
  }

  /**
   * 设置当前语言（不会持久化，持久化由 SettingsService 负责）
   */
  setLanguage(lang: AppLanguage): void {
    this.currentLang = lang;
  }

  /**
   * 获取当前语言
   */
  getLanguage(): AppLanguage {
    return this.currentLang;
  }

  /**
   * 获取语言显示标签
   */
  getLanguageLabel(): string {
    switch (this.currentLang) {
      case AppLanguage.ZH_CN:
        return '中文';
      case AppLanguage.EN_US:
        return 'English';
      default: {
        const detected: AppLanguage = this.detectSystemLang();
        if (detected === AppLanguage.ZH_CN) {
          return '\u4E2D\u6587 (System)';
        }
        return 'English (System)';
      }
    }
  }

  // ══════════════════════════════════════════════
  //  系统语言检测
  // ══════════════════════════════════════════════

  private detectSystemLang(): AppLanguage {
    try {
      const sysLang: string = i18n.System.getSystemLanguage();
      if (sysLang === 'zh' || sysLang.indexOf('zh') === 0) {
        return AppLanguage.ZH_CN;
      }
    } catch (e) {
      // 忽略检测失败
    }
    return AppLanguage.EN_US;
  }

  // ══════════════════════════════════════════════
  //  字符串映射表初始化
  // ══════════════════════════════════════════════

  private static buildZhMap(): Map<string, string> {
    const m: Map<string, string> = new Map<string, string>();
    // App
    m.set('app_title', '\u89C6\u9891\u64AD\u653E\u5668');
    m.set('app_online', '\u5728\u7EBF');
    m.set('index_online_btn', '\u5728\u7EBF\u5F71\u89C6');
    m.set('app_unknown_video', '\u672A\u77E5\u89C6\u9891');
    // Index
    m.set('index_scanning', '\u6B63\u5728\u626B\u63CF\u89C6\u9891...');
    m.set('index_no_videos', '\u6682\u672A\u53D1\u73B0\u89C6\u9891\u6587\u4EF6');
    m.set('index_rescan', '\u91CD\u65B0\u626B\u63CF');
    m.set('index_no_history', '\u6682\u65E0\u64AD\u653E\u8BB0\u5F55');
    m.set('index_history_hint', '\u64AD\u653E\u89C6\u9891\u540E\u4F1A\u81EA\u52A8\u8BB0\u5F55');
    m.set('index_played_to', '\u64AD\u653E\u81F3');
    m.set('index_no_favorites', '\u6682\u65E0\u6536\u85CF');
    m.set('index_favorites_hint', '\u957F\u6309\u89C6\u9891\u6DFB\u52A0\u6536\u85CF');
    m.set('index_local_videos', '\u672C\u5730\u89C6\u9891');
    m.set('index_recent', '\u6700\u8FD1\u64AD\u653E');
    m.set('index_favorites', '\u6211\u7684\u6536\u85CF');
    // Settings
    m.set('settings_title', '\u8BBE\u7F6E');
    m.set('settings_playback', '\u64AD\u653E');
    m.set('settings_auto_play_next', '\u81EA\u52A8\u64AD\u653E\u4E0B\u4E00\u96C6');
    m.set('settings_hw_accel', '\u786C\u4EF6\u52A0\u901F');
    m.set('settings_background_play', '\u540E\u53F0\u64AD\u653E');
    m.set('settings_default_speed', '\u9ED8\u8BA4\u901F\u5EA6');
    m.set('settings_display', '\u663E\u793A');
    m.set('settings_orientation', '\u5C4F\u5E55\u65B9\u5411');
    m.set('settings_show_subtitles', '\u663E\u793A\u5B57\u5E55');
    m.set('settings_language', '\u8BED\u8A00');
    m.set('settings_network', '\u7F51\u7EDC');
    m.set('settings_wifi_only', '\u4EC5 Wi-Fi');
    m.set('settings_data', '\u6570\u636E');
    m.set('settings_history', '\u64AD\u653E\u5386\u53F2');
    m.set('settings_records', '\u6761\u8BB0\u5F55');
    m.set('settings_clear', '\u6E05\u9664');
    m.set('settings_about', '\u5173\u4E8E');
    m.set('settings_version', '\u7248\u672C');
    m.set('lang_system', '\u8DDF\u968F\u7CFB\u7EDF');
    m.set('lang_zh', '\u4E2D\u6587');
    m.set('lang_en', 'English');
    // Orientation labels
    m.set('orient_landscape', '\u6A2A\u5C4F');
    m.set('orient_portrait', '\u7AD6\u5C4F');
    m.set('orient_auto', '\u81EA\u52A8');
    // Control panel
    m.set('cp_load_subtitles', '\u52A0\u8F7D\u5B57\u5E55');
    m.set('cp_sub_delay', '\u5B57\u5E55\u5EF6\u8FDF');
    m.set('cp_quality', '\u6E05\u6670\u5EA6');
    m.set('cp_danmaku', '\u5F39\u5E55');
    m.set('cp_send_danmaku', '\u53D1\u9001\u5F39\u5E55...');
    m.set('cp_on', '\u5F00');
    m.set('cp_off', '\u5173');
    m.set('cp_auto', '\u81EA\u52A8');
    m.set('cp_brightness', '\u4EAE\u5EA6');
    m.set('cp_volume', '\u97F3\u91CF');
    m.set('cp_pip', '\u753B\u4E2D\u753B');
    // Error
    m.set('error_playback_failed', '\u64AD\u653E\u5931\u8D25');
    m.set('error_code', '\u9519\u8BEF\u4EE3\u7801');
    m.set('error_unknown', '\u672A\u77E5\u64AD\u653E\u9519\u8BEF');
    m.set('error_close', '\u5173\u95ED');
    m.set('error_retry', '\u91CD\u8BD5');
    m.set('error_show_detail', '\u663E\u793A\u8BE6\u60C5');
    m.set('error_hide_detail', '\u9690\u85CF\u8BE6\u60C5');
    m.set('error_retry_failed', '\u91CD\u8BD5\u5931\u8D25');
    // Online
    m.set('online_title', '\u5728\u7EBF\u89C6\u9891');
    m.set('online_add_source', '\u6DFB\u52A0\u5A92\u4F53\u6E90');
    m.set('online_source_name', '\u6E90\u540D\u79F0');
    m.set('online_source_url', '\u6E90\u5730\u5740 (URL)');
    m.set('online_confirm_add', '\u786E\u8BA4\u6DFB\u52A0');
    m.set('online_movies', '\u5F71\u89C6');
    m.set('online_live', '\u76F4\u64AD');
    m.set('online_no_movie_source', '\u6682\u672A\u6DFB\u52A0\u5F71\u89C6\u6E90');
    m.set('online_no_movie_hint', '\u70B9\u51FB\u53F3\u4E0A\u89D2 + \u6DFB\u52A0');
    m.set('online_all', '\u5168\u90E8');
    m.set('online_no_content', '\u6682\u65E0\u5185\u5BB9');
    m.set('online_no_iptv_source', '\u6682\u672A\u6DFB\u52A0 IPTV \u76F4\u64AD\u6E90');
    m.set('online_no_iptv_hint', '\u70B9\u51FB\u53F3\u4E0A\u89D2 + \u6DFB\u52A0 M3U/TXT \u6E90');
    m.set('online_no_channel', '\u6682\u65E0\u9891\u9053');
    m.set('online_channels', '\u4E2A\u9891\u9053');
    m.set('online_add', '\u6DFB\u52A0\u6E90');
    // Search
    m.set('search_placeholder', '\u641C\u7D22\u89C6\u9891...');
    m.set('search_btn', '\u641C\u7D22');
    m.set('search_empty', '\u8F93\u5165\u5173\u952E\u8BCD\u641C\u7D22\u89C6\u9891');
    m.set('search_no_result', '\u672A\u627E\u5230\u76F8\u5173\u89C6\u9891');
    m.set('search_result_count', '\u4E2A\u7ED3\u679C');
    // Media card
    m.set('card_rating', '\u8BC4\u5206');
    m.set('card_dl', '\u4E0B\u8F7D');
    // Time
    m.set('time_just_now', '\u521A\u521A');
    m.set('time_yesterday', '\u6628\u5929');
    m.set('time_hour_suffix', '\u5C0F\u65F6\u524D');
    m.set('time_min_suffix', '\u5206\u949F\u524D');
    m.set('time_day_suffix', '\u5929\u524D');
    m.set('time_h', '\u5C0F\u65F6');
    m.set('time_m', '\u5206');
    return m;
  }

  private static buildEnMap(): Map<string, string> {
    const m: Map<string, string> = new Map<string, string>();
    // App
    m.set('app_title', 'Video Player');
    m.set('app_online', 'Online');
    m.set('index_online_btn', 'Online Videos');
    m.set('app_unknown_video', 'Unknown video');
    // Index
    m.set('index_scanning', 'Scanning videos...');
    m.set('index_no_videos', 'No video files found');
    m.set('index_rescan', 'Rescan');
    m.set('index_no_history', 'No playback history');
    m.set('index_history_hint', 'Records automatically after playing');
    m.set('index_played_to', 'Played to');
    m.set('index_no_favorites', 'No favorites yet');
    m.set('index_favorites_hint', 'Long-press a video to add to favorites');
    m.set('index_local_videos', 'Local Videos');
    m.set('index_recent', 'Recently Played');
    m.set('index_favorites', 'My Favorites');
    // Settings
    m.set('settings_title', 'Settings');
    m.set('settings_playback', 'Playback');
    m.set('settings_auto_play_next', 'Auto play next');
    m.set('settings_hw_accel', 'Hardware acceleration');
    m.set('settings_background_play', 'Background play');
    m.set('settings_default_speed', 'Default speed');
    m.set('settings_display', 'Display');
    m.set('settings_orientation', 'Orientation');
    m.set('settings_show_subtitles', 'Show subtitles');
    m.set('settings_language', 'Language');
    m.set('settings_network', 'Network');
    m.set('settings_wifi_only', 'Wi-Fi only');
    m.set('settings_data', 'Data');
    m.set('settings_history', 'Playback history');
    m.set('settings_records', 'records');
    m.set('settings_clear', 'Clear');
    m.set('settings_about', 'About');
    m.set('settings_version', 'Version');
    m.set('lang_system', 'System');
    m.set('lang_zh', '\u4E2D\u6587');
    m.set('lang_en', 'English');
    // Orientation labels
    m.set('orient_landscape', 'Landscape');
    m.set('orient_portrait', 'Portrait');
    m.set('orient_auto', 'Auto');
    // Control panel
    m.set('cp_load_subtitles', 'Load subtitles');
    m.set('cp_sub_delay', 'Sub delay');
    m.set('cp_quality', 'Quality');
    m.set('cp_danmaku', 'Danmaku');
    m.set('cp_send_danmaku', 'Send danmaku...');
    m.set('cp_on', 'ON');
    m.set('cp_off', 'OFF');
    m.set('cp_auto', 'Auto');
    m.set('cp_brightness', 'Brightness');
    m.set('cp_volume', 'Volume');
    m.set('cp_pip', 'PiP');
    // Error
    m.set('error_playback_failed', 'Playback failed');
    m.set('error_code', 'Error code');
    m.set('error_unknown', 'Unknown playback error.');
    m.set('error_close', 'Close');
    m.set('error_retry', 'Retry');
    m.set('error_show_detail', 'Show detail');
    m.set('error_hide_detail', 'Hide detail');
    m.set('error_retry_failed', 'Retry failed.');
    // Online
    m.set('online_title', 'Online Videos');
    m.set('online_add_source', 'Add Media Source');
    m.set('online_source_name', 'Source Name');
    m.set('online_source_url', 'Source URL');
    m.set('online_confirm_add', 'Confirm Add');
    m.set('online_movies', 'Movies');
    m.set('online_live', 'Live');
    m.set('online_no_movie_source', 'No movie source added');
    m.set('online_no_movie_hint', 'Tap + to add source');
    m.set('online_all', 'All');
    m.set('online_no_content', 'No content');
    m.set('online_no_iptv_source', 'No IPTV source added');
    m.set('online_no_iptv_hint', 'Tap + to add M3U/TXT source');
    m.set('online_no_channel', 'No channels');
    m.set('online_channels', 'channels');
    m.set('online_add', 'Add Source');
    // Search
    m.set('search_placeholder', 'Search videos...');
    m.set('search_btn', 'Search');
    m.set('search_empty', 'Enter keywords to search videos');
    m.set('search_no_result', 'No results found');
    m.set('search_result_count', 'results');
    // Media card
    m.set('card_rating', 'Rating');
    m.set('card_dl', 'DL');
    // Time
    m.set('time_just_now', 'Just now');
    m.set('time_yesterday', 'Yesterday');
    m.set('time_hour_suffix', 'h ago');
    m.set('time_min_suffix', 'm ago');
    m.set('time_day_suffix', 'd ago');
    m.set('time_h', 'h');
    m.set('time_m', 'm');
    return m;
  }
}
