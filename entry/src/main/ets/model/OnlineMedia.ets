/**
 * 在线视频数据模型
 */

/**
 * 在线视频条目（影视）
 */
export interface OnlineVideoItem {
  id: string;
  title: string;
  url: string;
  thumbnail?: string;
  duration?: number;
  category?: string;
  description?: string;
  year?: string;
  rating?: string;
  actors?: string;
  director?: string;
}

/**
 * IPTV 频道
 */
export interface IptvChannel {
  id: string;
  name: string;
  url: string;
  group?: string;
  logo?: string;
  epgId?: string;
}

/**
 * 媒体源配置
 */
export interface MediaSource {
  id: string;
  name: string;
  type: 'movie' | 'iptv';
  url: string;
  lastUpdated: number;
  enabled: boolean;
}

/**
 * 影视 JSON API 响应 — 通用 CatVod/T3 类格式
 */
export interface MovieApiCategory {
  type_id: string;
  type_name: string;
}

export interface MovieApiItem {
  vod_id: string;
  vod_name: string;
  vod_pic?: string;
  vod_remarks?: string;
  type_id?: string;
  type_name?: string;
  vod_content?: string;
  vod_actor?: string;
  vod_director?: string;
  vod_year?: string;
  vod_duration?: string;
  vod_score?: string;
  vod_play_from?: string;
  vod_play_url?: string;
}

export interface MovieApiResponse {
  code?: number;
  msg?: string;
  page?: number;
  pagecount?: number;
  limit?: number;
  total?: number;
  class?: MovieApiCategory[];
  list?: MovieApiItem[];
}

/**
 * 影视 JSON API — 苹果CMS 格式
 */
export interface AppleCmsItem {
  vod_id: number;
  vod_name: string;
  vod_pic: string;
  vod_remarks: string;
  type_name: string;
  vod_content: string;
  vod_actor: string;
  vod_director: string;
  vod_year: string;
  vod_score: string;
  vod_play_url: string;
}

export interface AppleCmsResponse {
  code: number;
  msg: string;
  page: number;
  pagecount: number;
  limit: number;
  total: number;
  list: AppleCmsItem[];
}

/**
 * 影视 JSON — 简易格式
 */
export interface SimpleMovieItem {
  id?: string;
  name?: string;
  title?: string;
  url: string;
  pic?: string;
  thumbnail?: string;
  category?: string;
  type?: string;
  duration?: number;
  desc?: string;
  year?: string;
}

export interface SimpleMovieResponse {
  name?: string;
  source?: string;
  videos?: SimpleMovieItem[];
  list?: SimpleMovieItem[];
}

/**
 * IPTV JSON 格式
 */
export interface IptvJsonChannel {
  name: string;
  url: string;
  group?: string;
  logo?: string;
  id?: string;
}

export interface IptvJsonResponse {
  name?: string;
  channels?: IptvJsonChannel[];
  list?: IptvJsonChannel[];
}
