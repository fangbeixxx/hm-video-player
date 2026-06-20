import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { VideoPlayerView } from '../components/VideoPlayerView';

interface PlayerRouteParams {
  videoId?: string;
  videoPath?: string;
  videoTitle?: string;
  seekTo?: number;
}

@Entry
@Component
struct PlayerPage {
  @State videoId: string = '';
  @State videoPath: string = '';
  @State videoTitle: string = '';
  @State seekTo: number = 0;
  @State safeAreaTop: number = 0;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as PlayerRouteParams;
    console.info('[PlayerPage] route params:', JSON.stringify(params));
    if (params) {
      this.videoId = params.videoId || '';
      this.videoPath = params.videoPath || '';
      this.videoTitle = params.videoTitle || 'Unknown video';
      this.seekTo = params.seekTo || 0;
      console.info('[PlayerPage] videoId:', this.videoId);
      console.info('[PlayerPage] videoPath:', this.videoPath);
      console.info('[PlayerPage] videoTitle:', this.videoTitle);
      console.info('[PlayerPage] seekTo:', this.seekTo);
    } else {
      console.error('[PlayerPage] NO route params received!');
    }
    await this.initSafeArea();
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
      // 顶部安全区域占位
      Column()
        .width('100%')
        .height(this.safeAreaTop)
        .backgroundColor('#000000')

      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor('#FFFFFF')
          .onClick(() => router.back())

        Text(this.videoTitle)
          .fontSize(16)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 12 })
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#000000')

      VideoPlayerView({
        videoPath: this.videoPath,
        videoTitle: this.videoTitle,
        videoId: this.videoId,
        onBack: () => router.back()
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
