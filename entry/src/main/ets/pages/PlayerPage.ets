import { router } from '@kit.ArkUI';
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

  aboutToAppear(): void {
    const params = router.getParams() as PlayerRouteParams;
    if (params) {
      this.videoId = params.videoId || '';
      this.videoPath = params.videoPath || '';
      this.videoTitle = params.videoTitle || 'Unknown video';
      this.seekTo = params.seekTo || 0;
    }
  }

  build() {
    Column() {
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
