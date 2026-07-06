import { DanmakuEngine } from '../utils/DanmakuEngine';
import { DanmakuItem } from '../model/DanmakuItem';

/**
 * 弹幕渲染层
 */
@Component
export struct DanmakuLayer {
  @Prop engine: DanmakuEngine;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;
  private renderTimerId: number = -1;
  private canvasWidth: number = 360;
  private canvasHeight: number = 640;
  private lastFrameTime: number = 0;
  private readonly fps: number = 45;

  aboutToAppear(): void {
    this.canvasReady = false;
  }

  aboutToDisappear(): void {
    this.stopRenderLoop();
  }

  private onReady(): void {
    this.canvasReady = true;
    this.engine.setCanvasSize(this.canvasWidth, this.canvasHeight);
    this.engine.start(Date.now());
    this.lastFrameTime = Date.now();
    this.startRenderLoop();
  }

  private startRenderLoop(): void {
    this.stopRenderLoop();
    const interval = 1000 / this.fps;
    this.renderTimerId = setInterval(() => {
      this.renderFrame();
    }, interval);
  }

  private stopRenderLoop(): void {
    if (this.renderTimerId >= 0) {
      clearInterval(this.renderTimerId);
      this.renderTimerId = -1;
    }
  }

  private renderFrame(): void {
    if (!this.canvasReady) return;

    const ctx = this.context;
    const now = Date.now();
    const delta = this.lastFrameTime > 0 ? now - this.lastFrameTime : 16.67;
    this.lastFrameTime = now;

    if (!this.engine.config.enabled) {
      ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
      return;
    }

    try {
      // Update engine with real delta
      this.engine.update(now, Math.min(delta, 50));

      // Clear canvas
      ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);

      // Render visible items
      const items = this.engine.getVisibleItems();
      for (const item of items) {
        this.drawDanmakuItem(ctx, item);
      }
    } catch (e) {
      console.error('[DanmakuLayer] render error: ' + JSON.stringify(e));
    }
  }

  private drawDanmakuItem(ctx: CanvasRenderingContext2D, item: DanmakuItem): void {
    const x = item.x;
    const y = item.y;

    ctx.save();
    ctx.globalAlpha = item.opacity;
    ctx.font = `${item.fontSize}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'bottom';

    // Stroke (outline)
    if (item.strokeWidth > 0) {
      ctx.strokeStyle = item.strokeColor;
      ctx.lineWidth = item.strokeWidth;
      ctx.lineJoin = 'round';
      ctx.strokeText(item.text, x, y);
    }

    // Fill
    ctx.fillStyle = item.color;
    ctx.fillText(item.text, x, y);

    ctx.restore();
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .backgroundColor('transparent')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.canvasWidth = newValue.width as number;
        this.canvasHeight = newValue.height as number;
        if (this.canvasReady) {
          this.engine.setCanvasSize(this.canvasWidth, this.canvasHeight);
        }
      })
      .onReady(() => {
        this.onReady();
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
