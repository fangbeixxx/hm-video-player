import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { VideoPlayerView } from '../components/VideoPlayerView';
import { PlayHistoryService } from '../service/PlayHistoryService';

interface PlayerRouteParams {
  videoId?: string;
  videoPath?: string;
  videoTitle?: string;
  seekTo?: number;
  sourceType?: string; // 'local' | 'online'
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

  async aboutToAppear(): Promise<void> {
    this.playerReady = false;
    const params = router.getParams() as PlayerRouteParams;
    console.info('[PlayerPage] route params:', JSON.stringify(params));
    if (params) {
      this.videoId = params.videoId || '';
      this.videoPath = params.videoPath || '';
      this.videoTitle = params.videoTitle || 'Unknown video';
      this.seekTo = params.seekTo || 0;
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
      console.info('[PlayerPage] videoId:', this.videoId);
      console.info('[PlayerPage] videoPath:', this.videoPath);
      console.info('[PlayerPage] videoTitle:', this.videoTitle);
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
          onBack: () => router.back()
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
