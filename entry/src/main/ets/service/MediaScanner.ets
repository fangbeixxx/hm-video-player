import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { Environment, fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { VideoItem } from '../model/VideoItem';
import { SortType, VideoSource } from '../common/Enums';
import { Constants } from '../common/Constants';
import { FFmpegNative } from '../native/FFmpegNative';

export class MediaScanner {
  private static instance: MediaScanner | null = null;
  private cachedVideos: VideoItem[] = [];
  private readonly supportedVideoExtensions: Array<string> = [
    '.mp4', '.m4v', '.mov', '.mkv', '.avi', '.flv', '.wmv', '.webm',
    '.ts', '.mpg', '.mpeg', '.vob', '.m2ts', '.rmvb', '.rm', '.3gp', '.asf', '.ogv'
  ];

  static getInstance(): MediaScanner {
    if (MediaScanner.instance === null) {
      MediaScanner.instance = new MediaScanner();
    }
    return MediaScanner.instance;
  }

  async scanVideos(forceRefresh: boolean = false): Promise<VideoItem[]> {
    console.info('[MediaScanner] scanVideos start, forceRefresh=' + forceRefresh);

    if (!forceRefresh && this.cachedVideos.length > 0) {
      console.info('[MediaScanner] return cached videos, count=' + this.cachedVideos.length);
      return this.cachedVideos;
    }

    const mergedVideos: VideoItem[] = [];
    const seenKeys: Array<string> = [];

    try {
      const context = getContext(this);
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const predicates = new dataSharePredicates.DataSharePredicates();

      predicates.equalTo('media_type', photoAccessHelper.PhotoType.VIDEO);

      const fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [
          photoAccessHelper.PhotoKeys.DURATION.toString(),
          photoAccessHelper.PhotoKeys.SIZE.toString(),
          photoAccessHelper.PhotoKeys.DATE_MODIFIED.toString(),
          photoAccessHelper.PhotoKeys.WIDTH.toString(),
          photoAccessHelper.PhotoKeys.HEIGHT.toString()
        ],
        predicates: predicates
      };

      console.info('[MediaScanner] start fetching videos from media library...');
      const fetchResult = await helper.getAssets(fetchOptions);
      const assets = await fetchResult.getAllObjects();
      console.info('[MediaScanner] media library count=' + assets.length);

      for (const asset of assets) {
        this.addVideoIfAbsent(seenKeys, mergedVideos, await this.convertToVideoItem(asset));
      }

      fetchResult.close();
    } catch (error) {
      console.error('[MediaScanner] media library scan failed: ' + JSON.stringify(error));
      console.error('[MediaScanner] media library error message: ' + (error as Error).message);
    }

    const fileSystemVideos = await this.scanFileSystem();
    for (const video of fileSystemVideos) {
      this.addVideoIfAbsent(seenKeys, mergedVideos, video);
    }

    console.info('[MediaScanner] Total videos scanned: ' + mergedVideos.length);
    this.cachedVideos = mergedVideos;
    return mergedVideos;
  }

  private async convertToVideoItem(asset: photoAccessHelper.PhotoAsset): Promise<VideoItem> {
    const duration = asset.get(photoAccessHelper.PhotoKeys.DURATION.toString()) as number;
    const size = asset.get(photoAccessHelper.PhotoKeys.SIZE.toString()) as number;
    const dateModified = asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED.toString()) as number;
    const width = asset.get(photoAccessHelper.PhotoKeys.WIDTH.toString()) as number;
    const height = asset.get(photoAccessHelper.PhotoKeys.HEIGHT.toString()) as number;

    // Generate thumbnail
    let thumbnailPath: string = '';
    try {
      thumbnailPath = await this.generateThumbnail(asset);
    } catch (e) {
      // Thumbnail generation is optional; continue without it
    }

    return {
      id: asset.uri,
      title: asset.displayName || 'Unknown',
      path: asset.uri,
      duration: duration || 0,
      size: size || 0,
      dateModified: dateModified || 0,
      width: width || 0,
      height: height || 0,
      thumbnailPath: thumbnailPath,
      source: VideoSource.LOCAL
    };
  }

  /**
   * 为媒体库视频生成缩略图
   */
  private async generateThumbnail(asset: photoAccessHelper.PhotoAsset): Promise<string> {
    try {
      const pixelMap: image.PixelMap = await asset.getThumbnail({
        width: Constants.THUMBNAIL_WIDTH,
        height: Constants.THUMBNAIL_HEIGHT
      } as photoAccessHelper.ThumbnailOptions);

      const packer = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 80
      };
      const arrayBuffer: ArrayBuffer = await packer.packing(pixelMap, packOpts);
      pixelMap.release();
      packer.release();

      // Save to cache directory
      const cacheDir = getContext(this).cacheDir;
      const thumbFileName = `thumb_${Date.now()}_${Math.floor(Math.random() * 10000)}.jpg`;
      const thumbPath = `${cacheDir}/${thumbFileName}`;

      const file = fileIo.openSync(thumbPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, arrayBuffer);
      fileIo.closeSync(file);

      return thumbPath;
    } catch (e) {
      console.warn('[MediaScanner] thumbnail generation failed: ' + JSON.stringify(e));
      return '';
    }
  }

  private async scanFileSystem(): Promise<VideoItem[]> {
    const videos: VideoItem[] = [];
    const roots = this.getFileSystemRoots();

    console.info('[MediaScanner] scanFileSystem roots=' + JSON.stringify(roots));

    for (const root of roots) {
      try {
        const entries = fileIo.listFileSync(root, {
          recursion: true,
          filter: {
            suffix: this.supportedVideoExtensions
          }
        });

        console.info('[MediaScanner] scan root=' + root + ', matches=' + entries.length);

        for (const entry of entries) {
          const fullPath = this.joinPath(root, entry);
          const video = this.buildVideoItemFromPath(fullPath);
          if (video !== null) {
            videos.push(video);
          }
        }
      } catch (error) {
        console.warn('[MediaScanner] scan root failed: ' + root + ', error=' + JSON.stringify(error));
      }
    }

    console.info('[MediaScanner] scanFileSystem count=' + videos.length);
    return videos;
  }

  async searchVideos(keyword: string): Promise<VideoItem[]> {
    console.info('[MediaScanner] searchVideos with keyword: ' + keyword);
    const videos = await this.scanVideos();
    const lowerKeyword = keyword.toLowerCase();
    const results = videos.filter((video: VideoItem) =>
      video.title.toLowerCase().indexOf(lowerKeyword) >= 0
    );
    console.info('[MediaScanner] search results count: ' + results.length);
    return results;
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
    console.info('[MediaScanner] cache cleared');
    this.cachedVideos = [];
  }

  private getFileSystemRoots(): Array<string> {
    const roots: Array<string> = [];

    try {
      roots.push(Environment.getUserDownloadDir());
    } catch (error) {
      console.warn('[MediaScanner] getUserDownloadDir failed: ' + JSON.stringify(error));
    }

    try {
      roots.push(Environment.getUserDocumentDir());
    } catch (error) {
      console.warn('[MediaScanner] getUserDocumentDir failed: ' + JSON.stringify(error));
    }

    const uniqueRoots: Array<string> = [];
    for (const root of roots) {
      if (root.length > 0 && uniqueRoots.indexOf(root) < 0) {
        uniqueRoots.push(root);
      }
    }
    return uniqueRoots;
  }

  private addVideoIfAbsent(seenKeys: Array<string>, videos: VideoItem[], video: VideoItem): void {
    const key = this.createVideoKey(video);
    if (seenKeys.indexOf(key) >= 0) {
      return;
    }
    seenKeys.push(key);
    videos.push(video);
  }

  private createVideoKey(video: VideoItem): string {
    const title = video.title.toLowerCase();
    return `${title}|${video.size}|${video.dateModified}`;
  }

  private joinPath(root: string, relativePath: string): string {
    if (relativePath.startsWith('/')) {
      return root + relativePath;
    }
    return root + '/' + relativePath;
  }

  private buildVideoItemFromPath(path: string): VideoItem | null {
    try {
      const stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        return null;
      }

      const mediaInfo = FFmpegNative.getMediaInfo(path);
      const durationMs = mediaInfo !== null && mediaInfo.duration > 0
        ? Math.floor(mediaInfo.duration * 1000)
        : 0;

      return {
        id: path,
        title: this.getFileName(path),
        duration: durationMs,
        path: path,
        size: stat.size,
        dateModified: stat.mtime * 1000,
        mimeType: this.guessMimeType(path),
        width: mediaInfo?.width || 0,
        height: mediaInfo?.height || 0,
        thumbnailPath: '',
        source: VideoSource.LOCAL
      };
    } catch (error) {
      console.warn('[MediaScanner] buildVideoItemFromPath failed: ' + path + ', error=' + JSON.stringify(error));
      return null;
    }
  }

  private getFileName(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    const index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  private guessMimeType(path: string): string {
    const lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.mp4') || lowerPath.endsWith('.m4v')) {
      return 'video/mp4';
    }
    if (lowerPath.endsWith('.mov')) {
      return 'video/quicktime';
    }
    if (lowerPath.endsWith('.mkv')) {
      return 'video/x-matroska';
    }
    if (lowerPath.endsWith('.avi')) {
      return 'video/x-msvideo';
    }
    if (lowerPath.endsWith('.webm')) {
      return 'video/webm';
    }
    if (lowerPath.endsWith('.3gp')) {
      return 'video/3gpp';
    }
    return 'video/*';
  }
}
