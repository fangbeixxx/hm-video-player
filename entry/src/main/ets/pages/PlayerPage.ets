import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { VideoPlayerView } from '../components/VideoPlayerView';
import { PlayHistoryService } from '../service/PlayHistoryService';
import { PlaylistItem } from '../model/VideoItem';

interface PlayerRouteParams {
  videoId?: string;
  videoPath?: string;
  videoTitle?: string;
  seekTo?: number;
  sourceType?: string;
  playlist?: PlaylistItem[];
  playlistIndex?: number;
}

@Entry
@Component
struct PlayerPage {
  @State videoId: string = '';
  @State videoPath: string = '';
  @State videoTitle: string = '';
  @State seekTo: number = 0;
  @State safeAreaTop: number = 0;
  @State playerReady: boolean = false;
  @State playlist: PlaylistItem[] = [];
  @State playlistIndex: number = 0;

  async aboutToAppear(): Promise<void> {
    this.playerReady = false;
    const params = router.getParams() as PlayerRouteParams;
    console.info('[PlayerPage] route params:', JSON.stringify(params));
    if (params) {
      this.videoId = params.videoId || '';
      this.videoPath = params.videoPath || '';
      this.videoTitle = params.videoTitle || 'Unknown video';
      this.seekTo = params.seekTo || 0;
      this.playlist = params.playlist || [];
      this.playlistIndex = params.playlistIndex || 0;

      if (this.seekTo <= 0) {
        let record = this.videoId.length > 0 ? await PlayHistoryService.getInstance().getRecord(this.videoId) : null;
        if (record === null && this.videoPath.length > 0) {
          const history = await PlayHistoryService.getInstance().getHistory();
          record = history.find((item) => item.path === this.videoPath) || null;
        }
        if (record && record.lastPosition > 0) {
          this.seekTo = record.lastPosition;
          console.info('[ResumeFlow] PlayerPage restore seekTo from history=' + this.seekTo + ' videoId=' + this.videoId + ' path=' + this.videoPath);
        }
      }
      console.info('[ResumeFlow] PlayerPage resolved seekTo=' + this.seekTo + ' videoId=' + this.videoId + ' path=' + this.videoPath);
    } else {
      console.error('[PlayerPage] NO route params received!');
    }
    await this.initSafeArea();
    this.playerReady = true;
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

  /**
   * 切换到上一个视频
   */
  private goToPrevious(): void {
    if (this.playlist.length === 0) return;
    const newIndex = this.playlistIndex > 0 ? this.playlistIndex - 1 : this.playlist.length - 1;
    this.switchToPlaylistIndex(newIndex);
  }

  /**
   * 切换到下一个视频
   */
  private goToNext(): void {
    if (this.playlist.length === 0) return;
    const newIndex = (this.playlistIndex + 1) % this.playlist.length;
    this.switchToPlaylistIndex(newIndex);
  }

  /**
   * 切换到指定索引的视频（重新加载页面）
   */
  private switchToPlaylistIndex(index: number): void {
    const item = this.playlist[index];
    router.replaceUrl({
      url: 'pages/PlayerPage',
      params: {
        videoId: item.id,
        videoPath: item.path,
        videoTitle: item.title,
        playlist: this.playlist,
        playlistIndex: index
      }
    });
  }

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.safeAreaTop)
        .backgroundColor('#000000')

      if (this.playerReady) {
        VideoPlayerView({
          videoPath: this.videoPath,
          videoTitle: this.videoTitle,
          videoId: this.videoId,
          seekTo: this.seekTo,
          onBack: () => router.back(),
          onPrevious: () => this.goToPrevious(),
          onNext: () => this.goToNext()
        })
          .layoutWeight(1)
      } else {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
