import { common } from '@kit.AbilityKit';

export enum PiPState {
  NONE = 'none',
  ACTIVE = 'active'
}

export interface PiPCallbacks {
  onStateChange: (state: PiPState) => void;
}

interface PiPContentConfig {
  title: string;
  subtitle: string;
}

interface PiPWindowController {
  destroy: () => void;
  updateContent: (content: PiPContentConfig) => void;
}

/**
 * 画中画管理器（最小实现）
 *
 * 依赖：module.json5 中 ability 需配置 supportPiPMode: true。
 * 当前 SDK 类型声明中 createPiPWindow 不可用，系统通过
 * supportPiPMode 在应用退到后台时自动触发画中画。
 * 此管理器负责跟踪画中画逻辑状态并在 UI 中同步。
 */
export class PiPManager {
  private static instance: PiPManager | null = null;
  private pipController: PiPWindowController | null = null;
  private currentState: PiPState = PiPState.NONE;
  private callbacks: PiPCallbacks | null = null;
  private appContext: common.UIAbilityContext | null = null;

  static getInstance(): PiPManager {
    if (PiPManager.instance === null) {
      PiPManager.instance = new PiPManager();
    }
    return PiPManager.instance;
  }

  setContext(ctx: common.UIAbilityContext): void {
    this.appContext = ctx;
  }

  get state(): PiPState {
    return this.currentState;
  }

  get isActive(): boolean {
    return this.currentState === PiPState.ACTIVE;
  }

  setCallbacks(cbs: PiPCallbacks): void {
    this.callbacks = cbs;
  }

  async enterPiP(title: string, isPlaying: boolean): Promise<boolean> {
    if (this.currentState !== PiPState.NONE || this.appContext === null) {
      return false;
    }
    // PiP window creation is deferred to system via supportPiPMode in module.json5.
    // This method tracks the logical state for UI indication.
    this.currentState = PiPState.ACTIVE;
    if (this.callbacks) {
      this.callbacks.onStateChange(PiPState.ACTIVE);
    }
    return true;
  }

  async exitPiP(): Promise<void> {
    if (this.currentState !== PiPState.ACTIVE) {
      return;
    }
    if (this.pipController) {
      try {
        this.pipController.destroy();
      } catch (error) {
        console.warn('[PiPManager] exit PiP controller destroy failed');
      }
      this.pipController = null;
    }
    this.currentState = PiPState.NONE;
    if (this.callbacks) {
      this.callbacks.onStateChange(PiPState.NONE);
    }
  }

  updatePlayState(isPlaying: boolean, title: string): void {
    if (!this.pipController) {
      return;
    }
    try {
      const content: PiPContentConfig = {
        title: title,
        subtitle: isPlaying ? 'Playing' : 'Paused'
      };
      this.pipController.updateContent(content);
    } catch (error) {
      // silently ignore
    }
  }
}
