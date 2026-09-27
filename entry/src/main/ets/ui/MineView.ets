import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionManager, SessionState, ServerCheckStatus } from '../auth/SessionManager';
import { EndpointProbe, probeCourseList } from '../api/CourseApi';
import { probeResourceEndpoints } from '../api/ResourceProbe';
import { probeStudy } from '../api/StudyProbe';
import { PageLoading } from './CoursesView';

const DOMAIN: number = 0x0a01;
const TAG: string = 'MineView';

@ComponentV2
export struct MineView {
  @Event onRequestLogin: () => void = () => {};
  private session: SessionManager = SessionManager.get();
  private listener: () => void = () => {};
  private active: boolean = false;
  @Local private ready: boolean = false;
  @Local private loggedIn: boolean = false;
  @Local private loginOrigin: string = '';
  @Local private savedAt: number = 0;
  @Local private savedDomains: string[] = [];
  @Local private serverCheck: ServerCheckStatus = ServerCheckStatus.UNCHECKED;
  @Local private probing: boolean = false;
  @Local private probes: EndpointProbe[] = [];
  @Local private logoutError: boolean = false;
  @Local private logoutConfirming: boolean = false;

  private syncSession(): void {
    const state: SessionState = this.session.snapshot();
    this.ready = state.ready;
    this.loggedIn = state.loggedIn;
    this.loginOrigin = state.loginOrigin;
    this.savedAt = state.savedAt;
    this.savedDomains = this.session.domains();
    this.serverCheck = state.serverCheck;
  }

  aboutToAppear(): void {
    this.active = true;
    this.listener = () => {
      if (this.active) this.syncSession();
    };
    this.session.subscribe(this.listener);
    this.syncSession();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.session.unsubscribe(this.listener);
  }

  private formatTime(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleString() : '';
  }

  private async probe(includeResources: boolean = false): Promise<void> {
    if (this.probing) return;
    this.probing = true;
    try {
      this.probes = await probeCourseList();
      let verified: boolean = false;
      for (const probe of this.probes) {
        if (probe.ok && probe.recognized) {
          verified = true;
        }
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
      const err: Error = error as Error;
      hilog.error(DOMAIN, TAG, '连接自检失败: %{public}s', err.message);
      this.session.setServerCheck(ServerCheckStatus.FAILED);
    } finally {
      this.probing = false;
    }
  }


  private async logout(): Promise<void> {
    this.logoutError = false;
    try {
      await this.session.logout();
    } catch (error) {
      const err: Error = error as Error;
      hilog.error(DOMAIN, TAG, '退出登录失败: %{public}s', err.message);
      this.logoutError = true;
    }
  }

  private async confirmLogout(): Promise<void> {
    if (this.logoutConfirming) return;
    this.logoutConfirming = true;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '退出登录', message: '退出后本机保存的登录凭证会被清除。',
        buttons: [{ text: '取消', color: $r('app.color.ui_text_secondary') },
          { text: '确认退出', color: $r('app.color.ui_error') }]
      });
      if (choice.index === 1 && this.active) await this.logout();
    } finally { this.logoutConfirming = false; }
  }

  build() {
    Column() {
      if (!this.ready) {
        Column() {
          PageLoading({ message: $r('app.string.loading_session') })
        }
        .width('100%').layoutWeight(1)
        .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
        .justifyContent(FlexAlign.Center)
      } else if (!this.loggedIn) {
        Column({ space: $r('app.float.ui_space_section') }) {
          Column({ space: $r('app.float.ui_space_section') }) {
            Row({ space: $r('app.float.ui_space_card') }) {
              SymbolGlyph($r('sys.symbol.person'))
                .fontSize($r('app.float.ui_size_guest_icon'))
                .fontColor([$r('app.color.ui_text_secondary')])
              Column({ space: $r('app.float.ui_space_content') }) {
                Text($r('app.string.mine_not_logged_in'))
                  .fontSize($r('app.float.ui_text_page_title'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ui_text_primary'))
                Text($r('app.string.mine_guest_description'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_secondary'))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')
            Button($r('app.string.login_action'))
              .width('100%')
              .height($r('app.float.ui_size_primary_button'))
              .fontSize($r('app.float.ui_text_button'))
              .borderRadius($r('app.float.ui_radius_button'))
              .backgroundColor($r('app.color.ui_accent'))
              .onClick(() => { this.onRequestLogin(); })
          }
          .width('100%')
          .padding($r('app.float.ui_space_card'))
          .backgroundColor($r('app.color.ui_surface'))
          .borderRadius($r('app.float.ui_radius_card'))
          Column({ space: $r('app.float.ui_space_content') }) {
            Text($r('app.string.mine_about_title'))
              .fontSize($r('app.float.ui_text_label'))
              .fontColor($r('app.color.ui_text_tertiary'))
            Text($r('app.string.EntryAbility_label'))
              .fontSize($r('app.float.ui_text_body'))
              .fontColor($r('app.color.ui_text_primary'))
            Text($r('app.string.sample_data_notice'))
              .fontSize($r('app.float.ui_text_label'))
              .fontColor($r('app.color.ui_text_secondary'))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding($r('app.float.ui_space_card'))
          .backgroundColor($r('app.color.ui_surface'))
          .borderRadius($r('app.float.ui_radius_card'))
        }
        .width('100%').layoutWeight(1)
        .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ListItem() {
            Column({ space: $r('app.float.ui_space_content') }) {
              Text($r('app.string.local_credentials_present'))
                .fontSize($r('app.float.ui_text_card_title'))
                .fontColor($r('app.color.ui_text_primary'))
                .fontWeight(FontWeight.Medium)
              Text($r('app.string.server_check_label'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_tertiary'))
              if (this.serverCheck === ServerCheckStatus.UNCHECKED) {
                Text($r('app.string.server_check_unchecked'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_secondary'))
              } else if (this.serverCheck === ServerCheckStatus.PASSED) {
                Text($r('app.string.server_check_passed'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_accent'))
              } else {
                Text($r('app.string.server_check_failed'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_error'))
              }
              Text($r('app.string.login_origin_label'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_tertiary'))
              Text(this.loginOrigin)
                .fontSize($r('app.float.ui_text_body'))
                .fontColor($r('app.color.ui_text_primary'))
              Text($r('app.string.saved_at_label'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_tertiary'))
              Text(this.formatTime(this.savedAt))
                .fontSize($r('app.float.ui_text_body'))
                .fontColor($r('app.color.ui_text_primary'))
              Text($r('app.string.saved_domains_label'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_tertiary'))
              ForEach(this.savedDomains, (domain: string) => {
                Text(domain)
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_secondary'))
              }, (domain: string) => domain)
            }
            .width('100%').alignItems(HorizontalAlign.Start)
            .padding($r('app.float.ui_space_card'))
            .backgroundColor($r('app.color.ui_surface'))
            .borderRadius($r('app.float.ui_radius_card'))
          }.margin({ top: $r('app.float.ui_space_page_top'), bottom: $r('app.float.ui_space_list') })
            .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          ListItem() {
            Column({ space: $r('app.float.ui_space_content') }) {
              Button($r('app.string.connection_probe'))
                .width('100%')
                .height($r('app.float.ui_size_primary_button'))
                .fontSize($r('app.float.ui_text_button'))
                .borderRadius($r('app.float.ui_radius_button'))
                .backgroundColor($r('app.color.ui_accent'))
                .enabled(!this.probing)
                .onClick(() => { this.probe(); })
              if (this.probing) {
                PageLoading({ message: $r('app.string.probe_running') })
                  .width('100%')
              }
              Button($r('app.string.resource_probe'))
                .width('100%')
                .height($r('app.float.ui_size_primary_button'))
                .fontSize($r('app.float.ui_text_button'))
                .fontColor($r('app.color.ui_accent'))
                .borderRadius($r('app.float.ui_radius_button'))
                .backgroundColor($r('app.color.ui_accent_soft'))
                .enabled(!this.probing)
                .onClick(() => { this.probe(true); })
              Button($r('app.string.logout'))
                .width('100%')
                .height($r('app.float.ui_size_primary_button'))
                .fontSize($r('app.float.ui_text_button'))
                .fontColor($r('app.color.ui_accent'))
                .borderRadius($r('app.float.ui_radius_button'))
                .backgroundColor($r('app.color.ui_accent_soft'))
                .enabled(!this.logoutConfirming)
                .onClick(() => { this.confirmLogout(); })
              if (this.logoutError) {
                Text($r('app.string.logout_error'))
                  .fontSize($r('app.float.ui_text_label'))
                  .fontColor($r('app.color.ui_error'))
              }
            }
            .width('100%')
            .padding($r('app.float.ui_space_card'))
            .backgroundColor($r('app.color.ui_surface'))
            .borderRadius($r('app.float.ui_radius_card'))
          }.margin({ bottom: this.probes.length === 0 ?
            $r('app.float.ui_space_page') : $r('app.float.ui_space_list') })
            .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
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
                  Text(probe.note)
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor($r('app.color.ui_text_secondary'))
                }
                if (probe.preview.length > 0) {
                  Text(probe.preview)
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor($r('app.color.ui_text_tertiary'))
                }
              }
              .width('100%').alignItems(HorizontalAlign.Start)
              .padding($r('app.float.ui_space_card'))
              .backgroundColor($r('app.color.ui_surface'))
              .borderRadius($r('app.float.ui_radius_card'))
            }.margin({ bottom: index === this.probes.length - 1 ?
              $r('app.float.ui_space_page') : $r('app.float.ui_space_list') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }, (probe: EndpointProbe) => probe.url)
        }.width('100%').layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .padding({ bottom: this.ready && this.loggedIn ? 0 : $r('app.float.ui_space_page') })
    .backgroundColor($r('app.color.ui_canvas'))
  }
}
