import {
  OnlineVideoItem,
  IptvChannel,
  MovieApiResponse,
  AppleCmsResponse,
  SimpleMovieResponse,
  IptvJsonResponse
} from '../model/OnlineMedia';

/**
 * 媒体源解析器
 */
export class SourceParser {
  private static idCounter: number = 0;

  private static nextId(): string {
    SourceParser.idCounter++;
    return `online_${Date.now()}_${SourceParser.idCounter}`;
  }

  /**
   * 解析 M3U / M3U8 格式
   */
  static parseM3u(content: string, sourceUrl: string): IptvChannel[] {
    const channels: IptvChannel[] = [];
    const lines = content.replace(/\r/g, '').split('\n');
    let currentName: string = '';
    let currentGroup: string = '';
    let currentLogo: string = '';

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) continue;
      if (line === '#EXTM3U') continue;

      if (line.startsWith('#EXTINF:')) {
        currentName = '';
        currentGroup = '';
        currentLogo = '';

        const groupMatch = line.match(/group-title="([^"]*)"/i);
        if (groupMatch) { currentGroup = groupMatch[1]; }

        const logoMatch = line.match(/tvg-logo="([^"]*)"/i);
        if (logoMatch) { currentLogo = logoMatch[1]; }

        const commaIdx = line.lastIndexOf(',');
        if (commaIdx >= 0) {
          currentName = line.substring(commaIdx + 1).trim();
        }
      } else if (line.startsWith('http://') || line.startsWith('https://') ||
                 line.startsWith('rtmp://') || line.startsWith('rtsp://')) {
        const name = currentName.length > 0 ? currentName : `Channel ${channels.length + 1}`;
        channels.push({
          id: SourceParser.nextId(),
          name: name,
          url: line,
          group: currentGroup.length > 0 ? currentGroup : undefined,
          logo: currentLogo.length > 0 ? currentLogo : undefined
        });
        currentName = '';
        currentGroup = '';
        currentLogo = '';
      }
    }
    return channels;
  }

  /**
   * 解析 TXT 格式
   */
  static parseTxt(content: string, sourceUrl: string): IptvChannel[] {
    const channels: IptvChannel[] = [];
    const lines = content.replace(/\r/g, '').split('\n');

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (line.length === 0) continue;
      if (line.startsWith('#') || line.startsWith('//')) continue;

      const commaIdx = line.indexOf(',');
      if (commaIdx < 0) {
        const parts = line.split(/\s+/);
        if (parts.length >= 2) {
          const url = parts[parts.length - 1];
          if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('rtmp://')) {
            const name = parts.slice(0, -1).join(' ');
            channels.push({ id: SourceParser.nextId(), name: name, url: url });
          }
        }
        continue;
      }

      const namePart = line.substring(0, commaIdx).trim();
      let urlPart = line.substring(commaIdx + 1).trim();
      let group: string | undefined = undefined;
      const hashIdx = urlPart.indexOf('#');
      if (hashIdx >= 0) {
        group = urlPart.substring(hashIdx + 1).trim();
        urlPart = urlPart.substring(0, hashIdx).trim();
      }

      if (urlPart.startsWith('http://') || urlPart.startsWith('https://') ||
          urlPart.startsWith('rtmp://') || urlPart.startsWith('rtsp://')) {
        channels.push({ id: SourceParser.nextId(), name: namePart, url: urlPart, group: group });
      }
    }
    return channels;
  }

  /**
   * 自动检测并解析 JSON 内容
   */
  static parseJson(content: string, sourceUrl: string): OnlineVideoItem[] | IptvChannel[] | null {
    // Try IPTV JSON first
    const iptvResult = SourceParser.tryParseIptvJson(content);
    if (iptvResult !== null && iptvResult.length > 0) {
      return iptvResult;
    }
    // Try movie JSON
    const movieResult = SourceParser.tryParseMovieJson(content);
    if (movieResult !== null && movieResult.length > 0) {
      return movieResult;
    }
    return null;
  }

  private static tryParseIptvJson(content: string): IptvChannel[] | null {
    try {
      const response: IptvJsonResponse = JSON.parse(content);
      if (response.channels !== undefined && response.channels.length > 0) {
        const channels: IptvChannel[] = [];
        for (const ch of response.channels) {
          const item: IptvChannel = {
            id: ch.id || SourceParser.nextId(),
            name: ch.name,
            url: ch.url,
            group: ch.group,
            logo: ch.logo
          };
          channels.push(item);
        }
        return channels;
      }
    } catch (e) {
      // Not IPTV JSON
    }
    return null;
  }

  private static tryParseMovieJson(content: string): OnlineVideoItem[] | null {
    // Try CatVod/T3 format
    try {
      const response: MovieApiResponse = JSON.parse(content);
      if (response.list !== undefined && response.list.length > 0) {
        const videos: OnlineVideoItem[] = [];
        for (const item of response.list) {
          const video: OnlineVideoItem = {
            id: item.vod_id || SourceParser.nextId(),
            title: item.vod_name || 'Unknown',
            url: item.vod_play_url || '',
            thumbnail: item.vod_pic,
            category: item.type_name,
            description: item.vod_content,
            year: item.vod_year,
            rating: item.vod_score,
            actors: item.vod_actor,
            director: item.vod_director
          };
          videos.push(video);
        }
        return videos;
      }
    } catch (e) {
      // Not CatVod format
    }

    // Try AppleCMS format
    try {
      const response: AppleCmsResponse = JSON.parse(content);
      if (response.list !== undefined && response.list.length > 0) {
        const videos: OnlineVideoItem[] = [];
        for (const item of response.list) {
          const video: OnlineVideoItem = {
            id: String(item.vod_id),
            title: item.vod_name || 'Unknown',
            url: item.vod_play_url || '',
            thumbnail: item.vod_pic,
            category: item.type_name,
            description: item.vod_content,
            year: item.vod_year,
            rating: item.vod_score,
            actors: item.vod_actor,
            director: item.vod_director
          };
          videos.push(video);
        }
        return videos;
      }
    } catch (e) {
      // Not AppleCMS format
    }

    // Try simple format
    try {
      const response: SimpleMovieResponse = JSON.parse(content);
      if (response.videos !== undefined && response.videos.length > 0) {
        const videos: OnlineVideoItem[] = [];
        for (const item of response.videos) {
          const video: OnlineVideoItem = {
            id: item.id || SourceParser.nextId(),
            title: item.name || item.title || 'Unknown',
            url: item.url,
            thumbnail: item.pic || item.thumbnail,
            category: item.category || item.type,
            duration: item.duration,
            description: item.desc,
            year: item.year
          };
          videos.push(video);
        }
        return videos;
      }
    } catch (e) {
      // Not simple format
    }

    return null;
  }

  /**
   * 检测内容类型
   */
  static detectContentType(content: string, url: string): 'movie' | 'iptv' {
    const lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.m3u') || lowerUrl.endsWith('.m3u8')) {
      return 'iptv';
    }
    if (content.includes('#EXTINF') || content.includes('#EXTM3U')) {
      return 'iptv';
    }
    if (lowerUrl.endsWith('.txt')) {
      return SourceParser.isTxtIptv(content) ? 'iptv' : 'movie';
    }
    // Default to movie for JSON/unknown
    return 'movie';
  }

  private static isTxtIptv(content: string): boolean {
    const lines = content.split('\n').filter(l => l.trim().length > 0 && !l.startsWith('#'));
    if (lines.length === 0) return false;
    let urlLineCount = 0;
    const checkLines = lines.slice(0, 10);
    for (const line of checkLines) {
      const parts = line.split(',');
      const lastPart = parts[parts.length - 1].trim().split('#')[0].trim();
      if (lastPart.startsWith('http://') || lastPart.startsWith('https://') ||
          lastPart.startsWith('rtmp://') || lastPart.startsWith('rtsp://')) {
        urlLineCount++;
      }
    }
    return urlLineCount >= Math.min(3, lines.length);
  }
}
