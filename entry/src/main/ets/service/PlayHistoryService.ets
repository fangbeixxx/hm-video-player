import { preferences } from '@kit.ArkData';
import { PlayRecord } from '../model/VideoItem';
import { Constants } from '../common/Constants';

/**
 * 播放历史服务
 * 管理播放记录的存储和读取
 */
export class PlayHistoryService {
  private static instance: PlayHistoryService | null = null;
  private prefs: preferences.Preferences | null = null;

  static getInstance(): PlayHistoryService {
    if (PlayHistoryService.instance === null) {
      PlayHistoryService.instance = new PlayHistoryService();
    }
    return PlayHistoryService.instance;
  }

  /**
   * 初始化 Preferences
   */
  private async getPrefs(): Promise<preferences.Preferences> {
    if (!this.prefs) {
      this.prefs = await preferences.getPreferences(getContext(this), Constants.PREFS_HISTORY);
    }
    return this.prefs;
  }

  /**
   * 保存播放记录
   */
  async saveRecord(record: PlayRecord): Promise<void> {
    const prefs = await this.getPrefs();
    const history = await this.getHistory();

    // 移除同一视频的旧记录
    const filtered = history.filter(h => h.videoId !== record.videoId);
    filtered.unshift(record);

    // 限制最大数量
    while (filtered.length > Constants.MAX_HISTORY_COUNT) {
      filtered.pop();
    }

    await prefs.put('history_list', JSON.stringify(filtered));
    await prefs.flush();
  }

  /**
   * 获取播放历史
   * @param limit 限制数量，0表示全部
   */
  async getHistory(limit: number = 0): Promise<PlayRecord[]> {
    const prefs = await this.getPrefs();
    const data = await prefs.get('history_list', '[]') as string;
    const history: PlayRecord[] = JSON.parse(data);
    return limit > 0 ? history.slice(0, limit) : history;
  }

  /**
   * 获取指定视频的播放记录
   */
  async getRecord(videoId: string): Promise<PlayRecord | null> {
    const history = await this.getHistory();
    return history.find(h => h.videoId === videoId) || null;
  }

  /**
   * 删除指定播放记录
   */
  async deleteRecord(videoId: string): Promise<void> {
    const prefs = await this.getPrefs();
    const history = await this.getHistory();
    const filtered = history.filter(h => h.videoId !== videoId);
    await prefs.put('history_list', JSON.stringify(filtered));
    await prefs.flush();
  }

  /**
   * 清空播放历史
   */
  async clearHistory(): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put('history_list', '[]');
    await prefs.flush();
  }

  /**
   * 收藏管理
   */
  async getFavorites(): Promise<string[]> {
    const prefs = await this.getPrefs();
    const data = await prefs.get('favorites_list', '[]') as string;
    return JSON.parse(data);
  }

  async addFavorite(videoId: string): Promise<void> {
    const prefs = await this.getPrefs();
    const favorites = await this.getFavorites();
    if (favorites.indexOf(videoId) < 0) {
      favorites.push(videoId);
      await prefs.put('favorites_list', JSON.stringify(favorites));
      await prefs.flush();
    }
  }

  async removeFavorite(videoId: string): Promise<void> {
    const prefs = await this.getPrefs();
    const favorites = (await this.getFavorites()).filter(id => id !== videoId);
    await prefs.put('favorites_list', JSON.stringify(favorites));
    await prefs.flush();
  }

  async isFavorite(videoId: string): Promise<boolean> {
    const favorites = await this.getFavorites();
    return favorites.indexOf(videoId) >= 0;
  }
}
