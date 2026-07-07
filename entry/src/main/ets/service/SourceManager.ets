import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import util from '@ohos.util';
import { MediaSource, OnlineVideoItem, IptvChannel } from '../model/OnlineMedia';
import { SourceParser } from '../utils/SourceParser';

const PREFS_NAME: string = 'online_sources';
const KEY_SOURCES: string = 'source_list';
const CACHE_PREFIX: string = 'source_cache_';

/**
 * 在线媒体源管理服务
 * 管理影视源和 IPTV 源的增删改查，支持持久化和内容缓存
 */
export class SourceManager {
  private static instance: SourceManager | null = null;
  private prefs: preferences.Preferences | null = null;
  private contentCache: Map<string, OnlineVideoItem[] | IptvChannel[]> = new Map();
  private appContext: common.Context | null = null;

  static getInstance(): SourceManager {
    if (SourceManager.instance === null) {
      SourceManager.instance = new SourceManager();
    }
    return SourceManager.instance;
  }

  setContext(ctx: common.Context): void {
    this.appContext = ctx;
  }

  private getCtx(): common.Context {
    if (this.appContext === null) {
      throw new Error('SourceManager: context not set');
    }
    return this.appContext;
  }

  private async getPrefs(): Promise<preferences.Preferences> {
    if (!this.prefs) {
      this.prefs = await preferences.getPreferences(this.getCtx(), PREFS_NAME);
    }
    return this.prefs;
  }

  // ==================== Source CRUD ====================

  /**
   * 获取所有媒体源
   */
  async getSources(): Promise<MediaSource[]> {
    const prefs = await this.getPrefs();
    const data = await prefs.get(KEY_SOURCES, '[]') as string;
    return JSON.parse(data) as MediaSource[];
  }

  /**
   * 添加媒体源
   */
  async addSource(name: string, url: string, type: 'movie' | 'iptv'): Promise<MediaSource> {
    const sources = await this.getSources();
    const source: MediaSource = {
      id: `src_${Date.now()}`,
      name: name,
      type: type,
      url: url,
      lastUpdated: 0,
      enabled: true
    };
    sources.push(source);
    await this.saveSources(sources);
    return source;
  }

  /**
   * 删除媒体源
   */
  async removeSource(sourceId: string): Promise<void> {
    const sources = await this.getSources();
    const filtered = sources.filter(s => s.id !== sourceId);
    await this.saveSources(filtered);
    this.contentCache.delete(CACHE_PREFIX + sourceId);
  }

  /**
   * 更新媒体源
   */
  async updateSource(source: MediaSource): Promise<void> {
    const sources = await this.getSources();
    const idx = sources.findIndex(s => s.id === source.id);
    if (idx >= 0) {
      sources[idx] = source;
      await this.saveSources(sources);
    }
  }

  private async saveSources(sources: MediaSource[]): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_SOURCES, JSON.stringify(sources));
    await prefs.flush();
  }

  // ==================== Content Fetching ====================

  /**
   * 从源 URL 获取并解析内容
   */
  async fetchSourceContent(source: MediaSource): Promise<OnlineVideoItem[] | IptvChannel[] | null> {
    // Check cache first (TTL 5 minutes)
    const cacheKey = CACHE_PREFIX + source.id;
    const cached = this.contentCache.get(cacheKey);
    const now = Date.now();
    if (cached && (now - source.lastUpdated) < 300000) {
      console.info('[SourceManager] using cached content for: ' + source.name);
      return cached;
    }

    console.info('[SourceManager] fetching content from: ' + source.url);
    const lowerUrl: string = source.url.toLowerCase();
    try {
      const content = await this.httpGet(source.url);
      if (content.length === 0) {
        console.warn('[SourceManager] empty response from: ' + source.url);
        return cached || null;
      }

      let result: OnlineVideoItem[] | IptvChannel[] | null = null;

      // Dispatch by file extension first, then by source type
      if (lowerUrl.endsWith('.m3u') || lowerUrl.endsWith('.m3u8')) {
        result = SourceParser.parseM3u(content, source.url);
      } else if (lowerUrl.endsWith('.txt')) {
        result = SourceParser.parseTxt(content, source.url);
      } else if (source.type === 'iptv') {
        // IPTV JSON source
        const parsed = SourceParser.parseJson(content, source.url);
        result = parsed;
      } else {
        // Movie JSON source
        if (content.trim().startsWith('{') || content.trim().startsWith('[')) {
          result = SourceParser.parseJson(content, source.url);
        }
      }

      // Update cache and timestamp
      if (result && result.length > 0) {
        this.contentCache.set(cacheKey, result);
        source.lastUpdated = now;
        await this.updateSource(source);
      }

      return result;
    } catch (error) {
      console.error('[SourceManager] fetch failed for ' + source.name + ': ' + JSON.stringify(error));
      // 对于无法拉取的 IPTV/M3U8 源，将 URL 本身作为一个频道返回
      if (source.type === 'iptv' || lowerUrl.endsWith('.m3u') || lowerUrl.endsWith('.m3u8')) {
        const fallback: IptvChannel = {
          id: source.id,
          name: source.name,
          url: source.url
        };
        return [fallback];
      }
      return cached || null;
    }
  }

  /**
   * 搜索影视内容（在已缓存的源中搜索）
   */
  async searchOnline(keyword: string): Promise<OnlineVideoItem[]> {
    const results: OnlineVideoItem[] = [];
    const sources = await this.getSources();
    const movieSources = sources.filter(s => s.type === 'movie' && s.enabled);

    for (const source of movieSources) {
      const content = await this.fetchSourceContent(source);
      if (content && content.length > 0) {
        const videos = content as OnlineVideoItem[];
        const lowerKw = keyword.toLowerCase();
        const matched = videos.filter(v => v.title.toLowerCase().includes(lowerKw));
        results.push(...matched);
      }
    }
    return results;
  }

  /**
   * 测试源 URL 是否可访问
   */
  async testSourceUrl(url: string): Promise<boolean> {
    try {
      const content = await this.httpGet(url);
      return content.length > 0;
    } catch (e) {
      return false;
    }
  }

  // ==================== HTTP Helper ====================

  private async httpGet(url: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const httpRequest = http.createHttp();
      httpRequest.request(
        url,
        {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Connection': 'keep-alive'
          },
          connectTimeout: 15000,
          readTimeout: 30000
        },
        (err, data) => {
          if (err) {
            reject(new Error('HTTP error: ' + JSON.stringify(err)));
          } else {
            let result = '';
            if (typeof data.result === 'string') {
              result = data.result;
            } else if (data.result instanceof ArrayBuffer) {
              const decoder = new util.TextDecoder('utf-8', { fatal: false, ignoreBOM: false });
              result = decoder.decode(new Uint8Array(data.result as ArrayBuffer));
            } else if (typeof data.result === 'object') {
              result = JSON.stringify(data.result);
            }
            resolve(result);
          }
          httpRequest.destroy();
        }
      );
    });
  }
}
