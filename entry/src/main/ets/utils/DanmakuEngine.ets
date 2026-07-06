import { DanmakuItem, DanmakuSourceItem, DanmakuConfig } from '../model/DanmakuItem';

/**
 * 弹幕引擎
 * 管理弹幕对象的生命周期：创建、移动、碰撞检测、回收
 */
export class DanmakuEngine {
  private pool: DanmakuItem[] = [];
  private active: DanmakuItem[] = [];
  private pending: DanmakuSourceItem[] = [];
  private idCounter: number = 0;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private laneCount: number = 0;
  private laneHeight: number = 0;
  private laneAvailability: number[] = []; // 每条轨道的可用时间戳
  private lastUpdateTime: number = 0;
  private started: boolean = false;

  // Config
  config: DanmakuConfig = {
    enabled: true,
    opacity: 0.85,
    speed: 1.0,
    displayArea: 0.75,
    fontSize: 16,
    maxItems: 80
  };

  // Colors pool for random danmaku colors
  private static readonly COLORS: string[] = [
    '#FFFFFF', '#FFEB3B', '#4CAF50', '#2196F3',
    '#FF9800', '#E91E63', '#00BCD4', '#FF4081',
    '#8BC34A', '#FF5722', '#9C27B0', '#3F51B5'
  ];

  private static readonly STROKE_COLORS: string[] = [
    '#000000', '#333333', '#000000', '#000000',
    '#000000', '#000000', '#000000', '#000000',
    '#333333', '#000000', '#000000', '#000000'
  ];

  /**
   * 设置画布尺寸
   */
  setCanvasSize(width: number, height: number): void {
    this.canvasWidth = width > 0 ? width : 360;
    this.canvasHeight = height > 0 ? height : 640;

    this.laneHeight = this.config.fontSize + 6;
    const areaHeight = this.canvasHeight * this.config.displayArea;
    this.laneCount = Math.max(1, Math.floor(areaHeight / this.laneHeight));
    this.laneAvailability = new Array(this.laneCount).fill(0);

    console.info('[Danmaku] canvas=' + this.canvasWidth + 'x' + this.canvasHeight +
      ' lanes=' + this.laneCount + ' laneHeight=' + this.laneHeight);
  }

  /**
   * 开始引擎（绑定时间基准）
   */
  start(currentTimeMs: number): void {
    this.started = true;
    this.lastUpdateTime = currentTimeMs;
  }

  /**
   * 停止引擎
   */
  stop(): void {
    this.started = false;
    this.clear();
  }

  /**
   * 加载弹幕数据（XML 或 JSON）
   */
  loadFromArray(items: DanmakuSourceItem[]): void {
    this.pending.push(...items);
    // Sort by time
    this.pending.sort((a, b) => a.time - b.time);
    console.info('[Danmaku] loaded ' + this.pending.length + ' source items');
  }

  /**
   * 解析 Bilibili XML 弹幕格式
   */
  parseXmlContent(xmlContent: string, totalDuration: number): void {
    const items: DanmakuSourceItem[] = [];
    const regex = /<d p="([^"]*)">(.*?)<\/d>/g;
    let match: RegExpExecArray | null;

    while ((match = regex.exec(xmlContent)) !== null) {
      const attrs: string = match[1];
      const text: string = match[2];
      const parts = attrs.split(',');

      if (parts.length >= 5) {
        const time = parseFloat(parts[0]);
        const mode = parseInt(parts[1]);
        const fontSize = parseInt(parts[2]);
        const color = parseInt(parts[3]);

        if (time <= totalDuration) {
          items.push({
            time: time,
            mode: mode,
            color: color,
            text: text,
            fontSize: fontSize
          });
        }
      }
    }

    console.info('[Danmaku] parsed ' + items.length + ' items from XML');
    this.loadFromArray(items);
  }

  /**
   * 用户发送弹幕
   */
  sendDanmaku(text: string, color?: string): void {
    const colorIdx = Math.floor(Math.random() * DanmakuEngine.COLORS.length);
    const item: DanmakuSourceItem = {
      time: 0, // immediate
      mode: 1,
      color: color ? this.hexToDec(color) : 0,
      text: text,
      fontSize: this.config.fontSize
    };
    this.pending.unshift(item);
  }

  /**
   * 更新引擎（每帧调用）
   * @param currentTimeMs 视频当前播放时间（毫秒）
   * @param deltaMs 距离上次更新的时间（毫秒）
   */
  update(currentTimeMs: number, deltaMs: number): void {
    if (!this.started || !this.config.enabled) return;

    const limitedDeltaMs = Math.min(deltaMs, 50); // cap delta for smoothness
    const currentTimeSec = currentTimeMs / 1000;

    // Spawn pending items
    this.spawnPending(currentTimeSec);

    // Move active items
    for (let i = this.active.length - 1; i >= 0; i--) {
      const item = this.active[i];
      // Mark lane available when item passes left edge
      if (item.x + item.width < -20) {
        item.visible = false;
        item.completed = true;
        this.active.splice(i, 1);
        this.pool.push(item);
      } else {
        item.x -= item.speed * (limitedDeltaMs / 16.67); // normalize to 60fps
        item.visible = item.x < this.canvasWidth + 10 && item.x + item.width > -10;
      }
    }

    // Update lane availability
    for (let i = 0; i < this.laneCount; i++) {
      if (this.laneAvailability[i] < currentTimeSec) {
        this.laneAvailability[i] = currentTimeSec;
      }
    }

    this.lastUpdateTime = currentTimeMs;
  }

  /**
   * 获取可见的弹幕条目（用于渲染）
   */
  getVisibleItems(): DanmakuItem[] {
    return this.active.filter(item => item.visible);
  }

  /**
   * 清空所有弹幕
   */
  clear(): void {
    this.pool.push(...this.active);
    this.active = [];
    this.pending = [];
    this.laneAvailability = new Array(this.laneCount).fill(0);
  }

  // ==================== Private ====================

  private spawnPending(currentTimeSec: number): void {
    const lookAhead = 1.0; // spawn items up to 1 second ahead

    while (this.pending.length > 0 && this.pending[0].time <= currentTimeSec + lookAhead) {
      if (this.active.length >= this.config.maxItems) break;

      const src = this.pending.shift();
      if (!src) break;

      // Find available lane
      const lane = this.findAvailableLane(currentTimeSec);
      if (lane < 0) {
        // All lanes busy, put back and try later
        this.pending.unshift(src);
        break;
      }

      const item = this.allocateItem(src, lane);
      this.active.push(item);

      // Calculate lane occupation time
      const traverseTime = (this.canvasWidth + item.width) / item.speed;
      this.laneAvailability[lane] = currentTimeSec + Math.min(traverseTime * 0.6, 3.0);
    }
  }

  private findAvailableLane(currentTimeSec: number): number {
    for (let i = 0; i < this.laneCount; i++) {
      if (this.laneAvailability[i] <= currentTimeSec + 0.3) {
        return i;
      }
    }
    return -1;
  }

  private allocateItem(src: DanmakuSourceItem, lane: number): DanmakuItem {
    // Try to reuse from pool
    let item = this.pool.pop();
    if (!item) {
      item = {
        id: this.idCounter++,
        text: '',
        color: '#FFFFFF',
        fontSize: this.config.fontSize,
        speed: 180,
        x: this.canvasWidth,
        y: 0,
        width: 0,
        strokeWidth: 1.2,
        strokeColor: '#000000',
        opacity: this.config.opacity,
        lane: 0,
        visible: true,
        completed: false
      };
    }

    const fontSize = src.fontSize || this.config.fontSize;
    const colorIdx = src.color > 0 ? (src.color % DanmakuEngine.COLORS.length) :
      Math.floor(Math.random() * DanmakuEngine.COLORS.length);

    item.text = src.text;
    item.color = DanmakuEngine.COLORS[colorIdx];
    item.strokeColor = DanmakuEngine.STROKE_COLORS[colorIdx];
    item.fontSize = fontSize;
    item.speed = (170 + Math.random() * 40) * this.config.speed;
    item.x = this.canvasWidth + 10;
    item.y = lane * this.laneHeight + this.laneHeight * 0.85;
    item.width = src.text.length * fontSize * 0.6;
    item.strokeWidth = 1.2;
    item.opacity = this.config.opacity;
    item.lane = lane;
    item.visible = true;
    item.completed = false;

    // Adjust x so long texts start further right
    if (item.width > this.canvasWidth * 0.5) {
      item.x = this.canvasWidth + item.width * 0.3;
    }

    return item;
  }

  private hexToDec(hex: string): number {
    const clean = hex.replace('#', '');
    return parseInt(clean, 16);
  }
}
