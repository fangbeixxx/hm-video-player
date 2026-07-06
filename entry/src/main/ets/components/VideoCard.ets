import { VideoSource } from '../common/Enums';
import { VideoItem } from '../model/VideoItem';
import { TimeUtils } from '../utils/TimeUtils';
import { FileUtils } from '../utils/FileUtils';

@Component
export struct VideoCard {
  @ObjectLink video: VideoItemObserved;
  @Prop showDuration: boolean = true;
  @Prop showSize: boolean = true;
  @Prop showDate: boolean = false;

  onClicked: (video: VideoItem) => void = () => {};

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (this.video.thumbnailPath && this.video.thumbnailPath.length > 0) {
            Image(this.video.thumbnailPath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          } else {
            Image($r('app.media.ic_video_placeholder'))
              .width(40)
              .height(40)
              .opacity(0.8)
          }
        }
        .width(200)
        .height(120)
        .borderRadius(8)
        .backgroundColor('#20232A')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        if (this.showDuration && this.video.duration > 0) {
          Text(TimeUtils.formatTime(this.video.duration))
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('rgba(0,0,0,0.7)')
            .margin({ right: 6, bottom: 6 })
        }
      }

      Column({ space: 6 }) {
        Text(this.video.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(22)

        if (this.showSize) {
          Text(FileUtils.formatSize(this.video.size))
            .fontSize(13)
            .fontColor('#999999')
        }

        if (this.showDate) {
          Text(TimeUtils.formatRelativeTime(this.video.dateModified))
            .fontSize(12)
            .fontColor('#BBBBBB')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(120)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
    .shadow({
      radius: 8,
      color: 'rgba(0,0,0,0.06)',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.onClicked(this.video);
    })
  }
}

@Observed
export class VideoItemObserved implements VideoItem {
  id: string = '';
  title: string = '';
  duration: number = 0;
  path: string = '';
  size: number = 0;
  dateModified: number = 0;
  mimeType?: string;
  width?: number;
  height?: number;
  thumbnailPath?: string;
  source: VideoSource = VideoSource.LOCAL;
  isFavorite?: boolean;

  constructor(item?: VideoItem) {
    if (item) {
      this.id = item.id;
      this.title = item.title;
      this.duration = item.duration;
      this.path = item.path;
      this.size = item.size;
      this.dateModified = item.dateModified;
      this.mimeType = item.mimeType;
      this.width = item.width;
      this.height = item.height;
      this.thumbnailPath = item.thumbnailPath;
      this.source = item.source;
      this.isFavorite = item.isFavorite;
    }
  }
}
