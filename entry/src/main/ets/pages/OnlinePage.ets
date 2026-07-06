import { router } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { SourceManager } from '../service/SourceManager';
import { DownloadManager } from '../service/DownloadManager';
import { MediaSource, OnlineVideoItem, IptvChannel, MovieApiCategory } from '../model/OnlineMedia';
import { MovieCard, ChannelCard, CategoryChip } from '../components/OnlineMediaCard';

/**
 * 在线视频页面
 * Tab: 影视 | 直播(IPTV)
 */
@Entry
@Component
struct OnlinePage {
  @State activeTab: number = 0;
  @State safeAreaTop: number = 0;

  // Movie tab
  @State isLoadingMovies: boolean = false;
  @State movieSources: MediaSource[] = [];
  @State selectedMovieSourceId: string = '';
  @State movies: OnlineVideoItem[] = [];
  @State movieCategories: MovieApiCategory[] = [];
  @State selectedCategoryId: string = '';
  @State filteredMovies: OnlineVideoItem[] = [];
  @State movieSearchKeyword: string = '';

  // IPTV tab
  @State isLoadingIptv: boolean = false;
  @State iptvSources: MediaSource[] = [];
  @State selectedIptvSourceId: string = '';
  @State iptvChannels: IptvChannel[] = [];
  @State channelGroups: string[] = [];
  @State selectedChannelGroup: string = '';
  @State filteredChannels: IptvChannel[] = [];

  // Add source dialog
  @State showAddSourceDialog: boolean = false;
  @State newSourceName: string = '';
  @State newSourceUrl: string = '';
  @State newSourceType: 'movie' | 'iptv' = 'movie';

  private sourceManager: SourceManager = SourceManager.getInstance();
  private downloadManager: DownloadManager = DownloadManager.getInstance();

  async aboutToAppear(): Promise<void> {
    this.sourceManager.setContext(getContext(this));
    this.downloadManager.setContext(getContext(this));
    await this.initSafeArea();
    await this.loadSources();
  }

  private async initSafeArea(): Promise<void> {
    try {
      const windowStage = window.getLastWindow(getContext(this));
      const mainWindow = await windowStage;
      const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.safeAreaTop = px2vp(area.topRect.height);
    } catch (e) {
      this.safeAreaTop = 0;
    }
  }

  private async loadSources(): Promise<void> {
    const allSources = await this.sourceManager.getSources();
    this.movieSources = allSources.filter(s => s.type === 'movie' && s.enabled);
    this.iptvSources = allSources.filter(s => s.type === 'iptv' && s.enabled);

    if (this.movieSources.length > 0 && this.selectedMovieSourceId.length === 0) {
      this.selectedMovieSourceId = this.movieSources[0].id;
      await this.loadMovies();
    }
    if (this.iptvSources.length > 0 && this.selectedIptvSourceId.length === 0) {
      this.selectedIptvSourceId = this.iptvSources[0].id;
      await this.loadIptvChannels();
    }
  }

  // ==================== Movie Tab ====================

  private async loadMovies(): Promise<void> {
    if (this.selectedMovieSourceId.length === 0) return;
    this.isLoadingMovies = true;

    const source = this.movieSources.find(s => s.id === this.selectedMovieSourceId);
    if (!source) {
      this.isLoadingMovies = false;
      return;
    }

    const content = await this.sourceManager.fetchSourceContent(source);
    // Extract movie items from union type
    const movieItems: OnlineVideoItem[] = [];
    if (content) {
      for (let i = 0; i < content.length; i++) {
        const item = content[i];
        const itemTitle = item['title'];
        const itemUrl = item['url'];
        if (itemTitle !== undefined && itemUrl !== undefined) {
          const video: OnlineVideoItem = {
            id: String(item['id'] || ''),
            title: String(itemTitle),
            url: String(itemUrl),
          };
          if (item['thumbnail'] !== undefined) {
            video.thumbnail = String(item['thumbnail']);
          }
          if (item['category'] !== undefined) {
            video.category = String(item['category']);
          }
          if (item['description'] !== undefined) {
            video.description = String(item['description']);
          }
          if (item['year'] !== undefined) {
            video.year = String(item['year']);
          }
          if (item['rating'] !== undefined) {
            video.rating = String(item['rating']);
          }
          if (item['actors'] !== undefined) {
            video.actors = String(item['actors']);
          }
          if (item['director'] !== undefined) {
            video.director = String(item['director']);
          }
          movieItems.push(video);
        }
      }
    }
    if (movieItems.length > 0) {
      this.movies = movieItems;
      // Extract unique categories
      const catSet: string[] = [];
      for (const m of this.movies) {
        if (m.category && catSet.indexOf(m.category) < 0) {
          catSet.push(m.category);
        }
      }
      const categories: MovieApiCategory[] = [];
      for (const c of catSet) {
        const cat: MovieApiCategory = { type_id: c, type_name: c };
        categories.push(cat);
      }
      this.movieCategories = categories;
      this.applyMovieFilters();
    }
    this.isLoadingMovies = false;
  }

  private applyMovieFilters(): void {
    let result = this.movies;
    if (this.selectedCategoryId.length > 0) {
      result = result.filter(m => m.category === this.selectedCategoryId);
    }
    if (this.movieSearchKeyword.trim().length > 0) {
      const kw = this.movieSearchKeyword.trim().toLowerCase();
      result = result.filter(m => m.title.toLowerCase().includes(kw));
    }
    this.filteredMovies = result;
  }

  private playMovie(item: OnlineVideoItem): void {
    if (item.url.length === 0) {
      console.warn('[OnlinePage] movie has no play URL');
      return;
    }
    router.pushUrl({
      url: 'pages/PlayerPage',
      params: {
        videoId: item.id,
        videoPath: item.url,
        videoTitle: item.title,
        sourceType: 'online'
      }
    });
  }

  // ==================== Download ====================

  private async startDownload(item: OnlineVideoItem): Promise<void> {
    console.info('[OnlinePage] start download: ' + item.title);
    await this.downloadManager.addTask(item.title, item.url);
  }

  private async loadIptvChannels(): Promise<void> {
    if (this.selectedIptvSourceId.length === 0) return;
    this.isLoadingIptv = true;

    const source = this.iptvSources.find(s => s.id === this.selectedIptvSourceId);
    if (!source) {
      this.isLoadingIptv = false;
      return;
    }

    const content = await this.sourceManager.fetchSourceContent(source);
    // Extract IPTV channels from union type
    const channelItems: IptvChannel[] = [];
    if (content) {
      for (let i = 0; i < content.length; i++) {
        const item = content[i];
        const itemUrl = item['url'];
        if (itemUrl !== undefined) {
          const channel: IptvChannel = {
            id: String(item['id'] || ''),
            name: String(item['name'] || ''),
            url: String(itemUrl),
          };
          if (item['group'] !== undefined) {
            channel.group = String(item['group']);
          }
          if (item['logo'] !== undefined) {
            channel.logo = String(item['logo']);
          }
          channelItems.push(channel);
        }
      }
    }
    if (channelItems.length > 0) {
      this.iptvChannels = channelItems;
      // Extract unique groups
      const groupSet: string[] = [];
      for (const ch of this.iptvChannels) {
        if (ch.group && groupSet.indexOf(ch.group) < 0) {
          groupSet.push(ch.group);
        }
      }
      this.channelGroups = groupSet;
      this.applyChannelFilters();
    }
    this.isLoadingIptv = false;
  }

  private applyChannelFilters(): void {
    let result = this.iptvChannels;
    if (this.selectedChannelGroup.length > 0) {
      result = result.filter(ch => ch.group === this.selectedChannelGroup);
    }
    this.filteredChannels = result;
  }

  private playChannel(channel: IptvChannel): void {
    router.pushUrl({
      url: 'pages/PlayerPage',
      params: {
        videoId: channel.id,
        videoPath: channel.url,
        videoTitle: channel.name,
        sourceType: 'online'
      }
    });
  }

  // ==================== Source Management ====================

  private async addSource(): Promise<void> {
    const name = this.newSourceName.trim();
    const url = this.newSourceUrl.trim();
    if (name.length === 0 || url.length === 0) return;

    await this.sourceManager.addSource(name, url, this.newSourceType);
    this.newSourceName = '';
    this.newSourceUrl = '';
    this.showAddSourceDialog = false;
    await this.loadSources();

    // Auto-select new source
    if (this.newSourceType === 'movie') {
      const srcs = await this.sourceManager.getSources();
      const movieSrcs = srcs.filter(s => s.type === 'movie');
      if (movieSrcs.length > 0) {
        this.selectedMovieSourceId = movieSrcs[movieSrcs.length - 1].id;
        this.movieSources = movieSrcs;
        await this.loadMovies();
      }
    } else {
      const srcs = await this.sourceManager.getSources();
      const iptvSrcs = srcs.filter(s => s.type === 'iptv');
      if (iptvSrcs.length > 0) {
        this.selectedIptvSourceId = iptvSrcs[iptvSrcs.length - 1].id;
        this.iptvSources = iptvSrcs;
        await this.loadIptvChannels();
      }
    }
  }

  private async removeSource(sourceId: string): Promise<void> {
    await this.sourceManager.removeSource(sourceId);
    await this.loadSources();
    // Reset selection if removed
    if (this.selectedMovieSourceId === sourceId) {
      this.selectedMovieSourceId = this.movieSources.length > 0 ? this.movieSources[0].id : '';
      this.movies = [];
      this.filteredMovies = [];
      if (this.selectedMovieSourceId.length > 0) {
        await this.loadMovies();
      }
    }
    if (this.selectedIptvSourceId === sourceId) {
      this.selectedIptvSourceId = this.iptvSources.length > 0 ? this.iptvSources[0].id : '';
      this.iptvChannels = [];
      this.filteredChannels = [];
      if (this.selectedIptvSourceId.length > 0) {
        await this.loadIptvChannels();
      }
    }
  }

  // ==================== Build ====================

  build() {
    Column() {
      // Safe area
      Column()
        .width('100%')
        .height(this.safeAreaTop)
        .backgroundColor('#FFFFFF')

      // Top navigation bar
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor('#333333')
          .onClick(() => router.back())

        Text('在线视频')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ left: 12 })
          .layoutWeight(1)

        // Add source button
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Text('+')
            .fontSize(20)
            .fontColor('#FFFFFF')
        }
        .width(32)
        .height(32)
        .backgroundColor('#FF4081')
        .onClick(() => {
          this.showAddSourceDialog = true;
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // Add source dialog (simple inline form)
      if (this.showAddSourceDialog) {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text('添加媒体源')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .layoutWeight(1)
            Text('X')
              .fontSize(16)
              .fontColor('#999999')
              .onClick(() => {
                this.showAddSourceDialog = false;
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            Button('影视')
              .fontSize(13)
              .type(ButtonType.Normal)
              .backgroundColor(this.newSourceType === 'movie' ? '#FF4081' : '#F0F0F0')
              .fontColor(this.newSourceType === 'movie' ? '#FFFFFF' : '#666666')
              .borderRadius(16)
              .height(30)
              .onClick(() => { this.newSourceType = 'movie'; })
            Button('IPTV')
              .fontSize(13)
              .type(ButtonType.Normal)
              .backgroundColor(this.newSourceType === 'iptv' ? '#FF4081' : '#F0F0F0')
              .fontColor(this.newSourceType === 'iptv' ? '#FFFFFF' : '#666666')
              .borderRadius(16)
              .height(30)
              .onClick(() => { this.newSourceType = 'iptv'; })
          }

          TextInput({ placeholder: '源名称', text: this.newSourceName })
            .height(40)
            .fontSize(14)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => { this.newSourceName = value; })

          TextInput({ placeholder: '源地址 (URL)', text: this.newSourceUrl })
            .height(40)
            .fontSize(14)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => { this.newSourceUrl = value; })

          Button('确认添加')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#FF4081')
            .borderRadius(8)
            .onClick(() => this.addSource())
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
      }

      Divider()

      // Tab: 影视 | 直播
      Tabs({ barPosition: BarPosition.Start, index: this.activeTab }) {
        TabContent() {
          this.MovieTabContent()
        }
        .tabBar(this.TabLabel('影视', this.activeTab === 0))

        TabContent() {
          this.IptvTabContent()
        }
        .tabBar(this.TabLabel('直播', this.activeTab === 1))
      }
      .onChange((index: number) => {
        this.activeTab = index;
      })
      .barWidth('100%')
      .barHeight(44)
      .scrollable(false)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  TabLabel(label: string, isActive: boolean) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(isActive ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(isActive ? '#FF4081' : '#999999')
      Divider()
        .width(24)
        .height(2)
        .color(isActive ? '#FF4081' : 'transparent')
        .borderRadius(1)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
  }

  // ==================== Movie Tab Content ====================

  @Builder
  MovieTabContent() {
    Column() {
      if (this.movieSources.length === 0) {
        this.EmptyStateBuilder('暂未添加影视源', '点击右上角 + 添加', () => { this.showAddSourceDialog = true; })
      } else {
        // Source selector
        this.SourceSelectorBuilder(
          this.movieSources,
          this.selectedMovieSourceId,
          (id: string) => {
            this.selectedMovieSourceId = id;
            this.selectedCategoryId = '';
            this.loadMovies();
          },
          (id: string) => { this.removeSource(id); }
        )

        // Category filter
        if (this.movieCategories.length > 0) {
          List() {
            ListItem() {
              Row({ space: 0 }) {
                CategoryChip({
                  label: '全部',
                  isActive: this.selectedCategoryId.length === 0,
                  onClicked: () => {
                    this.selectedCategoryId = '';
                    this.applyMovieFilters();
                  }
                })
                ForEach(this.movieCategories, (cat: MovieApiCategory) => {
                  CategoryChip({
                    label: cat.type_name,
                    isActive: this.selectedCategoryId === cat.type_id,
                    onClicked: () => {
                      this.selectedCategoryId = cat.type_id;
                      this.applyMovieFilters();
                    }
                  })
                })
              }
              .padding({ left: 8, right: 8 })
            }
          }
          .listDirection(Axis.Horizontal)
          .height(44)
          .scrollBar(BarState.Off)
        }

        // Movie list
        if (this.isLoadingMovies) {
          Column() {
            LoadingProgress().width(36).height(36)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.filteredMovies.length === 0) {
          Column({ space: 8 }) {
            Text('暂无内容')
              .fontSize(15)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.filteredMovies, (item: OnlineVideoItem) => {
              ListItem() {
                MovieCard({
                  item: item,
                  onClicked: (movie: OnlineVideoItem) => this.playMovie(movie),
                  onDownload: (movie: OnlineVideoItem) => this.startDownload(movie)
                })
              }
            })
          }
          .padding({ left: 16, right: 16, top: 4, bottom: 16 })
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== IPTV Tab Content ====================

  @Builder
  IptvTabContent() {
    Column() {
      if (this.iptvSources.length === 0) {
        this.EmptyStateBuilder('暂未添加 IPTV 直播源', '点击右上角 + 添加 M3U/TXT 源', () => { this.showAddSourceDialog = true; })
      } else {
        // Source selector
        this.SourceSelectorBuilder(
          this.iptvSources,
          this.selectedIptvSourceId,
          (id: string) => {
            this.selectedIptvSourceId = id;
            this.selectedChannelGroup = '';
            this.loadIptvChannels();
          },
          (id: string) => { this.removeSource(id); }
        )

        // Group filter
        if (this.channelGroups.length > 0) {
          List() {
            ListItem() {
              Row({ space: 0 }) {
                CategoryChip({
                  label: '全部',
                  isActive: this.selectedChannelGroup.length === 0,
                  onClicked: () => {
                    this.selectedChannelGroup = '';
                    this.applyChannelFilters();
                  }
                })
                ForEach(this.channelGroups, (group: string) => {
                  CategoryChip({
                    label: group,
                    isActive: this.selectedChannelGroup === group,
                    onClicked: () => {
                      this.selectedChannelGroup = group;
                      this.applyChannelFilters();
                    }
                  })
                })
              }
              .padding({ left: 8, right: 8 })
            }
          }
          .listDirection(Axis.Horizontal)
          .height(44)
          .scrollBar(BarState.Off)
        }

        // Channel list
        if (this.isLoadingIptv) {
          Column() {
            LoadingProgress().width(36).height(36)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.filteredChannels.length === 0) {
          Column({ space: 8 }) {
            Text('暂无频道')
              .fontSize(15)
              .fontColor('#999999')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Text(`${this.filteredChannels.length} 个频道`)
            .fontSize(12)
            .fontColor('#999999')
            .padding({ left: 16, top: 8, bottom: 4 })
            .width('100%')

          List({ space: 0 }) {
            ForEach(this.filteredChannels, (channel: IptvChannel) => {
              ListItem() {
                ChannelCard({
                  channel: channel,
                  onClicked: (ch: IptvChannel) => this.playChannel(ch)
                })
              }
            })
          }
          .divider({ strokeWidth: 0.5, color: '#F0F0F0' })
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== Shared Builders ====================

  @Builder
  SourceSelectorBuilder(sources: MediaSource[], selectedId: string,
                        onSelect: (id: string) => void,
                        onDelete: (id: string) => void) {
    List() {
      ListItem() {
        Row({ space: 6 }) {
          ForEach(sources, (src: MediaSource) => {
            Row({ space: 2 }) {
              Text(src.name)
                .fontSize(12)
                .fontColor(selectedId === src.id ? '#FFFFFF' : '#666666')
                .maxLines(1)
                .padding({ left: 10, right: 4, top: 5, bottom: 5 })
              if (selectedId === src.id && src.name.length > 0) {
                Text('X')
                  .fontSize(10)
                  .fontColor('rgba(255,255,255,0.7)')
                  .padding({ right: 6 })
                  .onClick(() => onDelete(src.id))
              }
            }
            .backgroundColor(selectedId === src.id ? '#FF4081' : '#F0F0F0')
            .borderRadius(14)
            .margin({ right: 6 })
            .onClick(() => onSelect(src.id))
          })
        }
        .padding({ left: 8, right: 8 })
      }
    }
    .listDirection(Axis.Horizontal)
    .height(40)
    .scrollBar(BarState.Off)
  }

  @Builder
  EmptyStateBuilder(title: string, subtitle: string, onAction: () => void) {
    Column({ space: 12 }) {
      Image($r('app.media.ic_empty'))
        .width(100)
        .height(100)
        .opacity(0.4)
      Text(title)
        .fontSize(16)
        .fontColor('#999999')
      Text(subtitle)
        .fontSize(13)
        .fontColor('#CCCCCC')
      Button('添加源')
        .fontSize(14)
        .onClick(() => onAction())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
