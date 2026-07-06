/**
 * 弹幕条目（运行时对象）
 */
export interface DanmakuItem {
  id: number;
  text: string;
  color: string;
  fontSize: number;       // vp
  speed: number;          // vp per second
  x: number;              // current x (vp)
  y: number;              // lane y (vp)
  width: number;          // measured text width (vp)
  strokeWidth: number;    // outline width
  strokeColor: string;    // outline color
  opacity: number;
  lane: number;
  visible: boolean;
  completed: boolean;
}

/**
 * 弹幕源数据（从文件或 API 加载）
 */
export interface DanmakuSourceItem {
  time: number;     // 出现时间（秒）
  mode: number;     // 1=滚动, 4=底部, 5=顶部
  color: number;    // 颜色（十进制）
  text: string;
  fontSize?: number;
}

/**
 * Bilibili XML 弹幕格式解析的原始条目
 */
export interface DanmakuXmlEntry {
  p: string;  // "time,mode,fontSize,color,..."
  text: string;
}

/**
 * 弹幕配置
 */
export interface DanmakuConfig {
  enabled: boolean;
  opacity: number;       // 0.0 - 1.0
  speed: number;         // 0.5 - 2.0
  displayArea: number;   // 0.25 | 0.5 | 0.75 | 1.0 (screen ratio)
  fontSize: number;      // base font size in vp
  maxItems: number;      // max concurrent danmaku items
}
