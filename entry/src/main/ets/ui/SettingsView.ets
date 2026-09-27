import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SessionManager, SessionState, ServerCheckStatus } from '../auth/SessionManager';
import { EndpointProbe, probeCourseList } from '../api/CourseApi';
import { probeResourceEndpoints } from '../api/ResourceProbe';
import { probeStudy } from '../api/StudyProbe';
import { PageLoading } from './CoursesView';

const DOMAIN: number = 0x0a01;
const TAG: string = 'SettingsView';

@ComponentV2
export struct SettingsView {
  private session: SessionManager = SessionManager.get();
  private listener: () => void = () => {};
  private active: boolean = false;
  private pref?: preferences.Preferences;
  @Local private remindersEnabled: boolean = true;
  @Local private prefReady: boolean = false;
  @Local private preferenceError: boolean = false;
  @Local private versionName: string = '';
  @Local private serverCheck: ServerCheckStatus = ServerCheckStatus.UNCHECKED;
  @Local private probing: boolean = false;
  @Local private probes: EndpointProbe[] = [];

  aboutToAppear(): void {
    this.active = true;
    this.listener = () => {
      if (this.active) this.serverCheck = this.session.snapshot().serverCheck;
    };
    this.session.subscribe(this.listener);
    this.serverCheck = this.session.snapshot().serverCheck;
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
    this.session.unsubscribe(this.listener);
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

  private async probe(includeResources: boolean = false): Promise<void> {
    if (this.probing) return;
    this.probing = true;
    try {
      this.probes = await probeCourseList();
      let verified: boolean = false;
      for (const probe of this.probes) {
        if (probe.ok && probe.recognized) verified = true;
      }
      this.session.setServerCheck(verified ? ServerCheckStatus.PASSED : ServerCheckStatus.FAILED);
      if (includeResources) {
        const context = this.getUIContext().getHostContext();
        if (context === undefined) throw new Error('无法取得自检样本目录');
        await probeResourceEndpoints(context.filesDir, (result: EndpointProbe) => {
          if (this.active) this.probes = this.probes.concat([result]);
        });
        await probeStudy(context.filesDir, (result: EndpointProbe) => {
          if (this.active) this.probes = this.probes.concat([result]);
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, '连接自检失败: %{public}s', (error as Error).message);
      this.session.setServerCheck(ServerCheckStatus.FAILED);
    } finally {
      this.probing = false;
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
      ListItemGroup({ header: this.groupHeader($r('app.string.settings_diagnostics')) }) {
        ListItem() {
          Column({ space: $r('app.float.ui_space_content') }) {
            Text($r('app.string.server_check_label'))
              .fontSize($r('app.float.ui_text_card_title'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ui_text_primary'))
            if (this.serverCheck === ServerCheckStatus.UNCHECKED) {
              Text($r('app.string.server_check_unchecked'))
                .fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_text_secondary'))
            } else if (this.serverCheck === ServerCheckStatus.PASSED) {
              Text($r('app.string.server_check_passed'))
                .fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_accent'))
            } else {
              Text($r('app.string.server_check_failed'))
                .fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_error'))
            }
            Button($r('app.string.connection_probe'))
              .width('100%').height($r('app.float.ui_size_primary_button'))
              .fontSize($r('app.float.ui_text_button'))
              .borderRadius($r('app.float.ui_radius_button'))
              .backgroundColor($r('app.color.ui_accent'))
              .enabled(!this.probing)
              .onClick(() => { this.probe(); })
            Button($r('app.string.resource_probe'))
              .width('100%').height($r('app.float.ui_size_primary_button'))
              .fontSize($r('app.float.ui_text_button'))
              .fontColor($r('app.color.ui_accent'))
              .borderRadius($r('app.float.ui_radius_button'))
              .backgroundColor($r('app.color.ui_accent_soft'))
              .enabled(!this.probing)
              .onClick(() => { this.probe(true); })
            if (this.probing) {
              PageLoading({ message: $r('app.string.probe_running') }).width('100%')
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
            .padding($r('app.float.ui_space_card'))
            .backgroundColor($r('app.color.ui_surface'))
            .borderRadius($r('app.float.ui_radius_card'))
        }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
        ForEach(this.probes, (probe: EndpointProbe, index: number) => {
          ListItem() {
            Column({ space: $r('app.float.ui_space_content') }) {
              Text(probe.url)
                .fontSize($r('app.float.ui_text_body'))
                .fontColor($r('app.color.ui_text_primary'))
              Text(`${probe.status}  ${probe.contentType}`)
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_secondary'))
              if (probe.note.length > 0) {
                Text(probe.note).fontSize($r('app.float.ui_text_label'))
                  .fontColor($r('app.color.ui_text_secondary'))
              }
              if (probe.preview.length > 0) {
                Text(probe.preview).fontSize($r('app.float.ui_text_label'))
                  .fontColor($r('app.color.ui_text_tertiary'))
              }
            }.width('100%').alignItems(HorizontalAlign.Start)
              .padding($r('app.float.ui_space_card'))
              .backgroundColor($r('app.color.ui_surface'))
              .borderRadius($r('app.float.ui_radius_card'))
          }.margin({ top: $r('app.float.ui_space_list') })
            .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
        }, (probe: EndpointProbe) => probe.url)
      }.margin({ bottom: $r('app.float.ui_space_section') })
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
      }.margin({ bottom: $r('app.float.ui_space_page') })
    }.width('100%').height('100%').backgroundColor($r('app.color.ui_canvas'))
  }
}
