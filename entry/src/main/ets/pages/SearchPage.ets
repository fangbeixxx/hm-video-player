import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { MediaScanner } from '../service/MediaScanner';
import { VideoCard, VideoItemObserved } from '../components/VideoCard';
import { VideoItem } from '../model/VideoItem';

/**
 * 搜索页面
 */
@Entry
@Component
struct SearchPage {
  @State searchKeyword: string = '';
  @State searchResults: VideoItemObserved[] = [];
  @State isSearching: boolean = false;
  @State hasSearched: boolean = false;
  @State safeAreaTop: number = 0;

  private scanner: MediaScanner = MediaScanner.getInstance();

  async aboutToAppear(): Promise<void> {
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

  /**
   * 执行搜索
   */
  private async doSearch(): Promise<void> {
    const keyword = this.searchKeyword.trim();
    if (!keyword) return;

    this.isSearching = true;
    this.hasSearched = true;

    try {
      const results = await this.scanner.searchVideos(keyword);
      this.searchResults = results.map(v => new VideoItemObserved(v));
    } catch (e) {
      console.error('Search failed:', e);
    }

    this.isSearching = false;
  }

  private goToPlayer(video: VideoItem): void {
    router.pushUrl({
      url: 'pages/PlayerPage',
      params: {
        videoId: video.id,
        videoPath: video.path,
        videoTitle: video.title
      }
    });
  }

  build() {
    Column() {
      // 顶部安全区域占位
      Column()
        .width('100%')
        .height(this.safeAreaTop)
        .backgroundColor('#FFFFFF')

      // 搜索栏
      Row({ space: 8 }) {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor('#666666')
          .onClick(() => router.back())

        TextInput({ placeholder: '搜索视频...', text: this.searchKeyword })
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor('#F0F0F0')
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })

        if (this.searchKeyword.length > 0) {
          Text('搜索')
            .fontSize(15)
            .fontColor('#FF4081')
            .onClick(() => this.doSearch())
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      Divider()

      // 搜索结果
      Column() {
        if (this.isSearching) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (!this.hasSearched) {
          Column({ space: 12 }) {
            Text('输入关键词搜索视频')
              .fontSize(15)
              .fontColor('#999999')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.searchResults.length === 0) {
          Column({ space: 12 }) {
            Text(`未找到与"${this.searchKeyword}"相关的视频`)
              .fontSize(15)
              .fontColor('#999999')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            Text(`找到 ${this.searchResults.length} 个结果`)
              .fontSize(13)
              .fontColor('#999999')
              .padding({ left: 24, top: 12, bottom: 4 })

            List({ space: 8 }) {
              ForEach(this.searchResults, (video: VideoItemObserved) => {
                ListItem() {
                  VideoCard({
                    video: video,
                    onClicked: (v: VideoItem) => this.goToPlayer(v)
                  })
                }
              })
            }
            .padding({ left: 16, right: 16 })
            .scrollBar(BarState.Off)
            .layoutWeight(1)
          }
          .width('100%')
          .height('100%')
        }
      }
      .layoutWeight(1)
      .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
