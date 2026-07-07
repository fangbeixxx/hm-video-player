import { PlayerError } from '../common/PlayerError';
import { AppLanguage } from '../common/Enums';
import { LocalizationManager } from '../utils/LocalizationManager';

@Component
export struct ErrorDialog {
  @Link visible: boolean;
  @Link error: PlayerError | null;

  onRetry: () => void = () => {};
  onDismiss: () => void = () => {};

  @StorageLink('appLanguage') appLanguage: AppLanguage = AppLanguage.SYSTEM;
  private loc: LocalizationManager = LocalizationManager.getInstance();

  @State showDetail: boolean = false;

  build() {
    Stack() {
      if (this.visible && this.error !== null) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.5)')

        Column({ space: 0 }) {
          Column({ space: 12 }) {
            Stack() {
              Circle()
                .width(64)
                .height(64)
                .fill('#FFF3E0')
              Text('!')
                .fontSize(32)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FF9800')
            }

            Text(this.error?.title || this.loc.getString('error_playback_failed'))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#333333')
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ top: 24, bottom: 16 })

          Row() {
            Text(`${this.loc.getString('error_code')}: ${this.error?.code || 0}`)
              .fontSize(11)
              .fontColor('#999999')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('#F5F5F5')
              .borderRadius(10)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ bottom: 16 })

          Divider()
            .color('#F0F0F0')
            .height(1)

          Column({ space: 8 }) {
            Text(this.error?.message || this.loc.getString('error_unknown'))
              .fontSize(15)
              .fontColor('#555555')
              .textAlign(TextAlign.Center)
              .padding({ top: 16 })

            if (this.error?.suggestion) {
              Text(this.error?.suggestion || '')
                .fontSize(13)
                .fontColor('#888888')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ left: 24, right: 24, top: 8 })
            }

            if (this.error?.detail) {
              Column() {
                Text(this.showDetail ? this.loc.getString('error_hide_detail') : this.loc.getString('error_show_detail'))
                  .fontSize(12)
                  .fontColor('#2196F3')
                  .onClick(() => {
                    this.showDetail = !this.showDetail;
                  })

                if (this.showDetail) {
                  Text(this.error?.detail || '')
                    .fontSize(11)
                    .fontColor('#777777')
                    .fontFamily('monospace')
                    .padding(12)
                    .width('100%')
                    .backgroundColor('#FAFAFA')
                    .borderRadius(8)
                    .margin({ top: 8 })
                    .copyOption(CopyOptions.LocalDevice)
                }
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 12 })
            }
          }
          .padding({ bottom: 20 })

          Divider()
            .color('#F0F0F0')
            .height(1)

          Row({ space: 0 }) {
            Button(this.loc.getString('error_close'))
              .fontSize(15)
              .fontColor('#999999')
              .backgroundColor('#FFFFFF')
              .layoutWeight(1)
              .height(48)
              .borderRadius(0)
              .onClick(() => {
                this.visible = false;
                this.showDetail = false;
                this.onDismiss();
              })

            if (this.error?.retryable) {
              Divider()
                .vertical(true)
                .color('#F0F0F0')
                .height(32)

              Button(this.loc.getString('error_retry'))
                .fontSize(15)
                .fontColor('#FF4081')
                .fontWeight(FontWeight.Medium)
                .backgroundColor('#FFFFFF')
                .layoutWeight(1)
                .height(48)
                .borderRadius(0)
                .onClick(() => {
                  this.visible = false;
                  this.showDetail = false;
                  this.onRetry();
                })
            }
          }
          .width('100%')
          .height(48)
        }
        .width('85%')
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .shadow({
          radius: 20,
          color: 'rgba(0,0,0,0.15)',
          offsetX: 0,
          offsetY: 8
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}

@Component
export struct ErrorToast {
  @Prop visible: boolean = false;
  @Prop message: string = '';
  @Prop retryable: boolean = false;

  onRetry: () => void = () => {};
  onDismiss: () => void = () => {};

  @StorageLink('appLanguage') appLanguage: AppLanguage = AppLanguage.SYSTEM;
  private loc: LocalizationManager = LocalizationManager.getInstance();

  build() {
    Row({ space: 8 }) {
      if (this.visible) {
        Text('!')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')

        Text(this.message)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .maxLines(2)

        if (this.retryable) {
          Text(this.loc.getString('error_retry'))
            .fontSize(13)
            .fontColor('#FFD740')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(4)
            .backgroundColor('rgba(255,255,255,0.15)')
            .onClick(() => {
              this.onRetry();
            })
        }

        Text('x')
          .fontSize(14)
          .fontColor('rgba(255,255,255,0.7)')
          .onClick(() => {
            this.onDismiss();
          })
      }
    }
    .width('100%')
    .height(this.visible ? 48 : 0)
    .padding({ left: 16, right: 16, top: this.visible ? 12 : 0, bottom: this.visible ? 12 : 0 })
    .backgroundColor(this.visible ? '#D32F2F' : 'transparent')
  }
}
