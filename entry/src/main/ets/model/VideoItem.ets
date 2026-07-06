import { VideoSource } from '../common/Enums';

export interface VideoItem {
  id: string;
  title: string;
  duration: number;
  path: string;
  size: number;
  dateModified: number;
  mimeType?: string;
  width?: number;
  height?: number;
  thumbnailPath?: string;
  source: VideoSource;
  isFavorite?: boolean;
}

export interface PlayRecord {
  videoId: string;
  title: string;
  path: string;
  lastPosition: number;
  duration: number;
  timestamp: number;
  thumbnailPath?: string;
}

export interface Playlist {
  id: string;
  name: string;
  videos: VideoItem[];
  createdAt: number;
  updatedAt: number;
}

export interface PlaylistItem {
  id: string;
  path: string;
  title: string;
}
