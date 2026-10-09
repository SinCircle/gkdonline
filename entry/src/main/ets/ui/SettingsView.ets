import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const DOMAIN: number = 0x0a01;
const TAG: string = 'SettingsView';

@ComponentV2
export struct SettingsView {
  private active: boolean = false;
  private pref?: preferences.Preferences;
  @Local private remindersEnabled: boolean = true;
  @Local private prefReady: boolean = false;
  @Local private preferenceError: boolean = false;
  @Local private versionName: string = '';

  aboutToAppear(): void {
    this.active = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) throw new Error('无法取得应用上下文');
      this.pref = preferences.getPreferencesSync(context, { name: 'ui_settings' });
      this.remindersEnabled = this.pref.getSync('reminders_enabled', true) as boolean;
      this.prefReady = true;
      this.preferenceError = false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '读取提醒设置失败: %{public}s', (error as Error).message);
      this.prefReady = false;
      this.preferenceError = true;
    }
    try {
      this.versionName = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '读取应用版本失败: %{public}s', (error as Error).message);
    }
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private saveReminderPreference(value: boolean): void {
    if (this.pref === undefined) {
      this.preferenceError = true;
      return;
    }
    try {
      this.pref.putSync('reminders_enabled', value);
      this.pref.flushSync();
      this.remindersEnabled = value;
      this.preferenceError = false;
      hilog.info(DOMAIN, TAG, '作业截止提醒设置为 %{public}s', String(value));
    } catch (error) {
      hilog.error(DOMAIN, TAG, '保存提醒设置失败: %{public}s', (error as Error).message);
      this.preferenceError = true;
      this.remindersEnabled = this.pref.getSync('reminders_enabled', !value) as boolean;
    }
  }

  @Builder
  private groupHeader(title: Resource) {
    Text(title)
      .fontSize($r('app.float.ui_text_label'))
      .fontColor($r('app.color.ui_text_tertiary'))
      .padding({ left: $r('app.float.ui_space_page'), bottom: $r('app.float.ui_space_content') })
  }

  build() {
    List() {
      ListItemGroup({ header: this.groupHeader($r('app.string.settings_notifications')) }) {
        ListItem() {
          Column({ space: $r('app.float.ui_space_content') }) {
            Row({ space: $r('app.float.ui_space_content') }) {
              Text($r('app.string.settings_work_reminder'))
                .fontSize($r('app.float.ui_text_body'))
                .fontColor($r('app.color.ui_text_primary')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.remindersEnabled })
                .enabled(this.prefReady)
                .onChange((value: boolean) => { this.saveReminderPreference(value); })
            }.width('100%')
            if (this.preferenceError) {
              Text($r('app.string.settings_save_error'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_error'))
            }
          }.width('100%').padding($r('app.float.ui_space_card'))
            .backgroundColor($r('app.color.ui_surface'))
            .borderRadius($r('app.float.ui_radius_card'))
        }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
      }.margin({ top: $r('app.float.ui_space_page_top'), bottom: $r('app.float.ui_space_section') })
      ListItemGroup({ header: this.groupHeader($r('app.string.mine_about_title')) }) {
        ListItem() {
          Column({ space: $r('app.float.ui_space_content') }) {
            Text($r('app.string.EntryAbility_label'))
              .fontSize($r('app.float.ui_text_body'))
              .fontColor($r('app.color.ui_text_primary'))
            Text(this.versionName)
              .fontSize($r('app.float.ui_text_label'))
              .fontColor($r('app.color.ui_text_secondary'))
            Text($r('app.string.service_domain'))
              .fontSize($r('app.float.ui_text_label'))
              .fontColor($r('app.color.ui_text_secondary'))
          }.width('100%').alignItems(HorizontalAlign.Start)
            .padding($r('app.float.ui_space_card'))
            .backgroundColor($r('app.color.ui_surface'))
            .borderRadius($r('app.float.ui_radius_card'))
        }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
      }.margin({ bottom: $r('app.float.ui_space_bottom_inset') })
    }.width('100%').height(LayoutPolicy.matchParent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.ui_canvas'))
  }
}
