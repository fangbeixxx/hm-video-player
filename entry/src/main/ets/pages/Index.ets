import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { MediaScanner } from '../service/MediaScanner';
import { PlayHistoryService } from '../service/PlayHistoryService';
import { VideoCard, VideoItemObserved } from '../components/VideoCard';
import { VideoItem, PlayRecord, PlaylistItem } from '../model/VideoItem';
import { SortType, AppLanguage } from '../common/Enums';
import { LocalizationManager } from '../utils/LocalizationManager';
import { TimeUtils } from '../utils/TimeUtils';
import { FileUtils } from '../utils/FileUtils';
import { SettingsService } from '../service/SettingsService';

/**
 * 首页 - 视频列表
 */
@Entry
@Component
struct Index {
  @State allVideos: VideoItemObserved[] = [];
  @State recentRecords: PlayRecord[] = [];
  @State favoriteVideos: VideoItemObserved[] = [];
  @State isLoading: boolean = true;
  @State selectedTab: number = 0;
  @State currentSort: SortType = SortType.DATE_MODIFIED;
  @State searchKeyword: string = '';
  @State safeAreaTop: number = 0; // 安全区域顶部高度

  @StorageLink('appLanguage') appLanguage: AppLanguage = AppLanguage.SYSTEM;
  private loc: LocalizationManager = LocalizationManager.getInstance();
  private scanner: MediaScanner = MediaScanner.getInstance();
  private historyService: PlayHistoryService = PlayHistoryService.getInstance();

  async aboutToAppear(): Promise<void> {
    // Load persisted language
    try {
      const savedLang: AppLanguage = await SettingsService.getInstance().getLanguage();
      this.loc.setLanguage(savedLang);
      AppStorage.set('appLanguage', savedLang);
    } catch (e) {
      // use default SYSTEM
    }
    await this.initSafeArea();
    await this.requestMediaPermission();
  }

  /**
   * 请求读取图片视频的运行时权限
   */
  private async requestMediaPermission(): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Array<Permissions> = [
      'ohos.permission.READ_IMAGEVIDEO',
      'ohos.permission.READ_MEDIA',
      'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY',
      'ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY'
    ];

    try {
      const context = getContext(this);
      const uiContext = context as common.UIAbilityContext;
      const data = await atManager.requestPermissionsFromUser(uiContext, permissions);
      const granted = data.authResults.some((result: number) =>
        result === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      );
      if (granted) {
        console.info('[Index] media read permission granted: ' + JSON.stringify(data.authResults));
      } else {
        console.warn('[Index] media read permission denied: ' + JSON.stringify(data.authResults));
      }
    } catch (e) {
      console.error('[Index] Request permission error: ' + JSON.stringify(e));
    }

    // 无论权限是否授予，都尝试加载数据（未授权时 scanner 会 graceful fallback）
    await this.loadData();
  }

  /**
   * 初始化安全区域
   */
  private async initSafeArea(): Promise<void> {
    try {
      const windowStage = window.getLastWindow(getContext(this));
      const mainWindow = await windowStage;
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.safeAreaTop = px2vp(area.topRect.height);
    } catch (e) {
      console.error('Get safe area failed: ' + JSON.stringify(e));
      this.safeAreaTop = 0;
    }
  }

  async onShow(): Promise<void> {
    // 页面显示时刷新最近播放和收藏
    await this.loadRecentRecords();
    await this.loadFavorites();
  }

  private async loadData(): Promise<void> {
    console.info('[Index] loadData start');
    this.isLoading = true;
    try {
      console.info('[Index] calling scanner.scanVideos...');
      const videos = await this.scanner.scanVideos();
      console.info('[Index] scanVideos returned, count=' + videos.length);
      this.allVideos = videos.map(v => new VideoItemObserved(v));
      console.info('[Index] allVideos set, count=' + this.allVideos.length);
      await this.loadRecentRecords();
    } catch (e) {
      console.error('[Index] Load data failed: ' + JSON.stringify(e));
      console.error('[Index] Error details: ' + JSON.stringify(e));
    }
    this.isLoading = false;
    console.info('[Index] loadData end, isLoading=' + this.isLoading);
  }

  private async loadRecentRecords(): Promise<void> {
    try {
      this.recentRecords = await this.historyService.getHistory(20);
    } catch (e) {
      console.error('Load history failed: ' + JSON.stringify(e));
    }
  }

  private async loadFavorites(): Promise<void> {
    try {
      const favIds = await this.historyService.getFavorites();
      // Match favorite IDs against all videos
      const all = await this.scanner.scanVideos();
      this.favoriteVideos = all
        .filter(v => favIds.indexOf(v.id) >= 0)
        .map(v => new VideoItemObserved(v));
    } catch (e) {
      console.error('Load favorites failed: ' + JSON.stringify(e));
    }
  }

  /**
   * 跳转播放页面
   */
  private goToPlayer(video: VideoItem): void {
    // Build playlist from allVideos for prev/next navigation
    const playlist: PlaylistItem[] = [];
    for (const v of this.allVideos) {
      const item: PlaylistItem = { id: v.id, path: v.path, title: v.title };
      playlist.push(item);
    }
    const currentIndex = this.allVideos.findIndex(v => v.id === video.id);

    router.pushUrl({
      url: 'pages/PlayerPage',
      params: {
        videoId: video.id,
        videoPath: video.path,
        videoTitle: video.title,
        playlist: playlist,
        playlistIndex: currentIndex >= 0 ? currentIndex : 0
      }
    });
  }

  /**
   * 继续播放历史记录
   */
  private continuePlay(record: PlayRecord): void {
    // Build playlist from allVideos for prev/next
    const playlist: PlaylistItem[] = [];
    for (const v of this.allVideos) {
      const item: PlaylistItem = { id: v.id, path: v.path, title: v.title };
      playlist.push(item);
    }
    const currentIndex = this.allVideos.findIndex(v => v.id === record.videoId);

    router.pushUrl({
      url: 'pages/PlayerPage',
      params: {
        videoId: record.videoId,
        videoPath: record.path,
        videoTitle: record.title,
        seekTo: record.lastPosition,
        playlist: playlist,
        playlistIndex: currentIndex >= 0 ? currentIndex : 0
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
          Text(this.loc.getString('index_scanning'))
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
          Text(this.loc.getString('index_no_videos'))
            .fontSize(16)
            .fontColor('#999999')
          Button(this.loc.getString('index_rescan'))
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
          }, (video: VideoItemObserved) => video.id)
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
          Text(this.loc.getString('index_no_history'))
            .fontSize(16)
            .fontColor('#999999')
          Text(this.loc.getString('index_history_hint'))
            .fontSize(13)
            .fontColor('#CCCCCC')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.recentRecords, (record: PlayRecord) => {
            ListItem() {
              this.RecentRecordCard(record)
            }
          }, (record: PlayRecord) => record.videoId)
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

        Text(`${this.loc.getString('index_played_to')} ${TimeUtils.formatTime(record.lastPosition)} / ${TimeUtils.formatTime(record.duration)}`)
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
    Column() {
      if (this.favoriteVideos.length === 0) {
        Column({ space: 12 }) {
          Image($r('app.media.ic_favorite_border'))
            .width(80)
            .height(80)
            .opacity(0.3)
          Text(this.loc.getString('index_no_favorites'))
            .fontSize(16)
            .fontColor('#999999')
          Text(this.loc.getString('index_favorites_hint'))
            .fontSize(13)
            .fontColor('#CCCCCC')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.favoriteVideos, (video: VideoItemObserved) => {
            ListItem() {
              VideoCard({
                video: video,
                showDate: true,
                onClicked: (v: VideoItem) => this.goToPlayer(v)
              })
            }
          }, (video: VideoItemObserved) => video.id)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  // ========== 主布局 ==========

  build() {
    Column() {
      // 顶部安全区域占位
      Column()
        .width('100%')
        .height(this.safeAreaTop)
        .backgroundColor('#FFFFFF')

      // 顶部导航栏
      Row() {
        Text(this.loc.getString('app_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Blank()

        // 在线视频按钮
        Text(this.loc.getString('app_online'))
          .fontSize(14)
          .fontColor('#FF4081')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .border({ width: 1, color: '#FF4081', radius: 4 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/OnlinePage' });
          })

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
        .tabBar(this.TabItem(this.loc.getString('index_local_videos'), this.selectedTab === 0))

        TabContent() {
          this.RecentTab()
        }
        .tabBar(this.TabItem(this.loc.getString('index_recent'), this.selectedTab === 1))

        TabContent() {
          this.FavoritesTab()
        }
        .tabBar(this.TabItem(this.loc.getString('index_favorites'), this.selectedTab === 2))
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
