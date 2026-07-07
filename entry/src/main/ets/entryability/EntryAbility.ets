import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppLanguage } from '../common/Enums';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('appLanguage', AppLanguage.SYSTEM);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 设置全屏沉浸式
    windowStage.getMainWindow().then((win) => {
      const sysBarProps: window.SystemBarProperties = {
        statusBarColor: '#000000',
        navigationBarColor: '#000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarContentColor: '#FFFFFF'
      };
      win.setWindowSystemBarProperties(sysBarProps);
      // 平板默认全屏
      win.setWindowLayoutFullScreen(true);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'testTag', 'Content loaded successfully');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
    // PiP is triggered by the player view when user presses PiP button;
    // the system automatically enters PiP mode when supportPiPMode is enabled
    // and the app goes to background while video is playing.
  }
}
