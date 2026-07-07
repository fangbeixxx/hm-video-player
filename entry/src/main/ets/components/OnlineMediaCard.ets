import { OnlineVideoItem, IptvChannel } from '../model/OnlineMedia';
import { AppLanguage } from '../common/Enums';
import { LocalizationManager } from '../utils/LocalizationManager';

/**
 * 在线视频卡片组件（影视）
 */
@Component
export struct MovieCard {
  @Prop item: OnlineVideoItem;

  @StorageLink('appLanguage') appLanguage: AppLanguage = AppLanguage.SYSTEM;
  private loc: LocalizationManager = LocalizationManager.getInstance();

  onClicked: (item: OnlineVideoItem) => void = () => {};
  onDownload: (item: OnlineVideoItem) => void = () => {};

  build() {
    Row({ space: 12 }) {
      // Thumbnail placeholder
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          Image($r('app.media.ic_video_placeholder'))
            .width(40)
            .height(40)
            .opacity(0.8)
        }
        .width(120)
        .height(80)
        .borderRadius(8)
        .backgroundColor('#20232A')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        if (this.item.category) {
          Text(this.item.category)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .borderRadius(3)
            .backgroundColor('rgba(0,0,0,0.7)')
            .margin({ right: 4, bottom: 4 })
            .maxLines(1)
        }
      }

      Column({ space: 4 }) {
        Text(this.item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20)

        Row({ space: 8 }) {
          if (this.item.year) {
            Text(this.item.year)
              .fontSize(12)
              .fontColor('#999999')
          }
          if (this.item.rating) {
            Text(this.loc.getString('card_rating') + ': ' + this.item.rating)
              .fontSize(12)
              .fontColor('#FF9800')
          }
          if (this.item.duration && this.item.duration > 0) {
            Text(this.formatDuration(this.item.duration))
              .fontSize(12)
              .fontColor('#999999')
          }
        }

        if (this.item.description) {
          Text(this.item.description)
            .fontSize(12)
            .fontColor('#BBBBBB')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(80)
      .justifyContent(FlexAlign.Center)

      // Download action
      Text(this.loc.getString('card_dl'))
        .fontSize(11)
        .fontColor('#FF4081')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .border({ width: 1, color: '#FF4081', radius: 4 })
        .onClick(() => {
          this.onDownload(this.item);
        })
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .shadow({
      radius: 6,
      color: 'rgba(0,0,0,0.05)',
      offsetX: 0,
      offsetY: 1
    })
    .onClick(() => {
      this.onClicked(this.item);
    })
  }

  private formatDuration(seconds: number): string {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) return `${h}${this.loc.getString('time_h')}${m}${this.loc.getString('time_m')}`;
    return `${m}${this.loc.getString('time_m')}`;
  }
}

/**
 * IPTV 频道卡片组件
 */
@Component
export struct ChannelCard {
  @Prop channel: IptvChannel;

  onClicked: (channel: IptvChannel) => void = () => {};

  build() {
    Row({ space: 12 }) {
      // Logo / icon placeholder
      Column() {
        Text(this.channel.name.substring(0, 1))
          .fontSize(18)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
      }
      .width(44)
      .height(44)
      .borderRadius(8)
      .backgroundColor('#FF4081')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 2 }) {
        Text(this.channel.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.channel.group) {
          Text(this.channel.group)
            .fontSize(12)
            .fontColor('#999999')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Image($r('app.media.ic_play'))
        .width(20)
        .height(20)
        .fillColor('#999999')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      this.onClicked(this.channel);
    })
  }
}

/**
 * 分类标签
 */
@Component
export struct CategoryChip {
  @Prop label: string;
  @Prop isActive: boolean = false;

  onClicked: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(13)
      .fontColor(this.isActive ? '#FFFFFF' : '#666666')
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.isActive ? '#FF4081' : '#F0F0F0')
      .borderRadius(16)
      .margin({ right: 8 })
      .onClick(() => {
        this.onClicked();
      })
  }
}
