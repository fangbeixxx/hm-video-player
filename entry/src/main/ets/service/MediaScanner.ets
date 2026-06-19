import { VideoItem } from '../model/VideoItem';
import { SortType } from '../common/Enums';

export class MediaScanner {
  private static instance: MediaScanner | null = null;
  private cachedVideos: VideoItem[] = [];

  static getInstance(): MediaScanner {
    if (MediaScanner.instance === null) {
      MediaScanner.instance = new MediaScanner();
    }
    return MediaScanner.instance;
  }

  async scanVideos(forceRefresh: boolean = false): Promise<VideoItem[]> {
    if (!forceRefresh && this.cachedVideos.length > 0) {
      return this.cachedVideos;
    }

    this.cachedVideos = [];
    return this.cachedVideos;
  }

  async searchVideos(keyword: string): Promise<VideoItem[]> {
    const videos = await this.scanVideos();
    const lowerKeyword = keyword.toLowerCase();
    return videos.filter((video: VideoItem) => video.title.toLowerCase().indexOf(lowerKeyword) >= 0);
  }

  sortVideos(videos: VideoItem[], sortType: SortType, ascending: boolean = false): VideoItem[] {
    const sorted = videos.slice();
    const multiplier = ascending ? 1 : -1;

    switch (sortType) {
      case SortType.NAME:
        sorted.sort((a: VideoItem, b: VideoItem) => multiplier * a.title.localeCompare(b.title));
        break;
      case SortType.DATE_MODIFIED:
        sorted.sort((a: VideoItem, b: VideoItem) => multiplier * (a.dateModified - b.dateModified));
        break;
      case SortType.SIZE:
        sorted.sort((a: VideoItem, b: VideoItem) => multiplier * (a.size - b.size));
        break;
      case SortType.DURATION:
        sorted.sort((a: VideoItem, b: VideoItem) => multiplier * (a.duration - b.duration));
        break;
    }

    return sorted;
  }

  clearCache(): void {
    this.cachedVideos = [];
  }
}
