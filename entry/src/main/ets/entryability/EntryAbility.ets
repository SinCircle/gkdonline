import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { WorkNavigation } from '../data/WorkNavigation';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    this.acceptWorkWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.acceptWorkWant(want);
  }

  private acceptWorkWant(want: Want): void {
    const params: Record<string, Object> | undefined = want.parameters;
    const workId: Object | undefined = params?.['gkdWorkId'];
    const title: Object | undefined = params?.['gkdWorkTitle'];
    const detailUrl: Object | undefined = params?.['gkdWorkUrl'];
    if (typeof workId !== 'string' || typeof title !== 'string' || typeof detailUrl !== 'string' ||
      workId.length === 0 || detailUrl.length === 0) return;
    const courseId: Object | undefined = params?.['gkdCourseId'];
    const classId: Object | undefined = params?.['gkdClassId'];
    WorkNavigation.get().offerLink({ workId: workId, title: title, detailUrl: detailUrl,
      courseId: typeof courseId === 'string' ? courseId : '', classId: typeof classId === 'string' ? classId : '' });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
