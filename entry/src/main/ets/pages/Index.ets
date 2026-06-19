import { router } from '@kit.ArkUI';
import { MediaScanner } from '../service/MediaScanner';
import { PlayHistoryService } from '../service/PlayHistoryService';
import { VideoCard, VideoItemObserved } from '../components/VideoCard';
import { VideoItem, PlayRecord } from '../model/VideoItem';
import { SortType } from '../common/Enums';
import { TimeUtils } from '../utils/TimeUtils';
import { FileUtils } from '../utils/FileUtils';

/**
 * 首页 - 视频列表
 */
@Entry
@Component
struct Index {
  @State allVideos: VideoItemObserved[] = [];
  @State recentRecords: PlayRecord[] = [];
  @State isLoading: boolean = true;
  @State selectedTab: number = 0;
  @State currentSort: SortType = SortType.DATE_MODIFIED;
  @State searchKeyword: string = '';

  private scanner: MediaScanner = MediaScanner.getInstance();
  private historyService: PlayHistoryService = PlayHistoryService.getInstance();

  async aboutToAppear(): Promise<void> {
    await this.loadData();
  }

  async onShow(): Promise<void> {
    // 页面显示时刷新最近播放
    await this.loadRecentRecords();
  }

  private async loadData(): Promise<void> {
    this.isLoading = true;
    try {
      const videos = await this.scanner.scanVideos();
      this.allVideos = videos.map(v => new VideoItemObserved(v));
      await this.loadRecentRecords();
    } catch (e) {
      console.error('Load data failed:', e);
    }
    this.isLoading = false;
  }

  private async loadRecentRecords(): Promise<void> {
    try {
      this.recentRecords = await this.historyService.getHistory(20);
    } catch (e) {
      console.error('Load history failed:', e);
    }
  }

  /**
   * 跳转播放页面
   */
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

  /**
   * 继续播放历史记录
   */
  private continuePlay(record: PlayRecord): void {
    router.pushUrl({
      url: 'pages/PlayerPage',
      params: {
        videoId: record.videoId,
        videoPath: record.path,
        videoTitle: record.title,
        seekTo: record.lastPosition
      }
    });
  }

  /**
   * 刷新数据
   */
  private async refresh(): Promise<void> {
    this.scanner.clearCache();
    await this.loadData();
  }

  // ========== 子页面构建器 ==========

  @Builder
  AllVideosTab() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('正在扫描视频...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.allVideos.length === 0) {
        Column({ space: 12 }) {
          Image($r('app.media.ic_empty'))
            .width(120)
            .height(120)
            .opacity(0.5)
          Text('暂未发现视频文件')
            .fontSize(16)
            .fontColor('#999999')
          Button('重新扫描')
            .fontSize(14)
            .onClick(() => this.refresh())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.allVideos, (video: VideoItemObserved) => {
            ListItem() {
              VideoCard({
                video: video,
                showDate: true,
                onClicked: (v: VideoItem) => this.goToPlayer(v)
              })
            }
          })
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  RecentTab() {
    Column() {
      if (this.recentRecords.length === 0) {
        Column({ space: 12 }) {
          Text('暂无播放记录')
            .fontSize(16)
            .fontColor('#999999')
          Text('播放视频后会自动记录')
            .fontSize(13)
            .fontColor('#CCCCCC')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.recentRecords, (record: PlayRecord, index: number) => {
            ListItem() {
              this.RecentRecordCard(record)
            }
          })
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  RecentRecordCard(record: PlayRecord) {
    Row({ space: 12 }) {
      // 缩略图
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          Image($r('app.media.ic_video_placeholder'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
        .width(160)
        .height(90)
        .borderRadius(8)
        .backgroundColor('#1A1A2E')

        // 进度条
        Progress({
          value: record.duration > 0 ? (record.lastPosition / record.duration) * 100 : 0,
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(3)
          .color('#FF4081')
          .backgroundColor('rgba(255,255,255,0.3)')
      }

      // 信息
      Column({ space: 6 }) {
        Text(record.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`播放至 ${TimeUtils.formatTime(record.lastPosition)} / ${TimeUtils.formatTime(record.duration)}`)
          .fontSize(12)
          .fontColor('#999999')

        Text(TimeUtils.formatRelativeTime(record.timestamp))
          .fontSize(11)
          .fontColor('#CCCCCC')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(90)
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: 'rgba(0,0,0,0.06)',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => this.continuePlay(record))
  }

  @Builder
  FavoritesTab() {
    Column({ space: 12 }) {
      Image($r('app.media.ic_favorite_border'))
        .width(80)
        .height(80)
        .opacity(0.3)
      Text('收藏功能开发中')
        .fontSize(16)
        .fontColor('#999999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // ========== 主布局 ==========

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('视频播放器')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Blank()

        // 搜索按钮
        Image($r('app.media.ic_search'))
          .width(22)
          .height(22)
          .fillColor('#666666')
          .padding(8)
          .onClick(() => {
            router.pushUrl({ url: 'pages/SearchPage' });
          })

        // 设置按钮
        Image($r('app.media.ic_settings'))
          .width(22)
          .height(22)
          .fillColor('#666666')
          .padding(8)
          .margin({ left: 4 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/SettingsPage' });
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .backgroundColor('#FFFFFF')

      // Tab 栏
      Tabs({ barPosition: BarPosition.Start, index: this.selectedTab }) {
        TabContent() {
          this.AllVideosTab()
        }
        .tabBar(this.TabItem('本地视频', this.selectedTab === 0))

        TabContent() {
          this.RecentTab()
        }
        .tabBar(this.TabItem('最近播放', this.selectedTab === 1))

        TabContent() {
          this.FavoritesTab()
        }
        .tabBar(this.TabItem('我的收藏', this.selectedTab === 2))
      }
      .onChange((index: number) => {
        this.selectedTab = index;
      })
      .barWidth('100%')
      .barHeight(48)
      .scrollable(false)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  TabItem(title: string, isActive: boolean) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(isActive ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(isActive ? '#FF4081' : '#999999')

      // 选中指示线
      Divider()
        .width(24)
        .height(2)
        .color(isActive ? '#FF4081' : 'transparent')
        .borderRadius(1)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
  }
}
