import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager } from '@kit.AbilityKit';
import { SessionManager, SessionState } from '../auth/SessionManager';
import { PageLoading } from './CoursesView';

const DOMAIN: number = 0x0a01;
const TAG: string = 'MineView';

// HomeView is outside this task's edit boundary. Index installs the route here.
export class MineSettingsNavigation {
  static open: () => void = () => {};
}

@ComponentV2
export struct MineView {
  @Event onRequestLogin: () => void = () => {};
  private session: SessionManager = SessionManager.get();
  private listener: () => void = () => {};
  private active: boolean = false;
  @Local private ready: boolean = false;
  @Local private loggedIn: boolean = false;
  @Local private versionName: string = '';
  @Local private logoutError: boolean = false;
  @Local private logoutConfirming: boolean = false;

  private syncSession(): void {
    const state: SessionState = this.session.snapshot();
    this.ready = state.ready;
    this.loggedIn = state.loggedIn;
  }

  aboutToAppear(): void {
    this.active = true;
    this.listener = () => { if (this.active) this.syncSession(); };
    this.session.subscribe(this.listener);
    this.syncSession();
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

  @Builder
  private groupHeader(title: Resource) {
    Text(title)
      .fontSize($r('app.float.ui_text_label'))
      .fontColor($r('app.color.ui_text_tertiary'))
      .padding({ left: $r('app.float.ui_space_page'), bottom: $r('app.float.ui_space_content') })
  }

  build() {
    Column() {
      if (!this.ready) {
        Column() { PageLoading({ message: $r('app.string.loading_session') }) }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ListItemGroup({ header: this.groupHeader($r('app.string.mine_account_group')) }) {
            ListItem() {
              Column({ space: $r('app.float.ui_space_content') }) {
                Text(this.loggedIn ? $r('app.string.mine_logged_in') : $r('app.string.mine_not_logged_in'))
                  .fontSize($r('app.float.ui_text_card_title'))
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ui_text_primary'))
                Text(this.loggedIn ? $r('app.string.service_domain') : $r('app.string.mine_guest_description'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_secondary'))
              }.width('100%').alignItems(HorizontalAlign.Start)
                .padding($r('app.float.ui_space_card'))
                .backgroundColor($r('app.color.ui_surface'))
                .borderRadius($r('app.float.ui_radius_card'))
            }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
            ListItem() {
              Column({ space: $r('app.float.ui_space_content') }) {
                Button(this.loggedIn ? $r('app.string.logout') : $r('app.string.login_action'))
                  .width('100%').height($r('app.float.ui_size_primary_button'))
                  .fontSize($r('app.float.ui_text_button'))
                  .borderRadius($r('app.float.ui_radius_button'))
                  .backgroundColor(this.loggedIn ? $r('app.color.ui_accent_soft') : $r('app.color.ui_accent'))
                  .fontColor(this.loggedIn ? $r('app.color.ui_accent') : $r('app.color.ui_text_on_strong'))
                  .enabled(!this.logoutConfirming)
                  .onClick(() => { if (this.loggedIn) this.confirmLogout(); else this.onRequestLogin(); })
                if (this.logoutError) {
                  Text($r('app.string.logout_error'))
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor($r('app.color.ui_error'))
                }
              }.width('100%')
            }.margin({ top: $r('app.float.ui_space_list') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }.margin({ top: $r('app.float.ui_space_page_top'), bottom: $r('app.float.ui_space_section') })
          ListItemGroup({ header: this.groupHeader($r('app.string.settings_title')) }) {
            ListItem() {
              Row() {
                Text($r('app.string.settings_title'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_primary')).layoutWeight(1)
                Text('›').fontSize($r('app.float.ui_text_page_title'))
                  .fontColor($r('app.color.ui_text_tertiary'))
              }.width('100%').padding($r('app.float.ui_space_card'))
                .backgroundColor($r('app.color.ui_surface'))
                .borderRadius($r('app.float.ui_radius_card'))
            }.onClick(() => { MineSettingsNavigation.open(); })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }.margin({ bottom: $r('app.float.ui_space_section') })
          ListItemGroup({ header: this.groupHeader($r('app.string.mine_about_title')) }) {
            ListItem() {
              Row() {
                Text($r('app.string.EntryAbility_label'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_primary')).layoutWeight(1)
                Text(this.versionName)
                  .fontSize($r('app.float.ui_text_label'))
                  .fontColor($r('app.color.ui_text_secondary'))
              }.width('100%').padding($r('app.float.ui_space_card'))
                .backgroundColor($r('app.color.ui_surface'))
                .borderRadius($r('app.float.ui_radius_card'))
            }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }.margin({ bottom: $r('app.float.ui_space_page') })
          ListItem() {
            Column() {}.height($r('app.float.ui_space_floating_bar'))
          }.id('mine-floating-bar-spacer')
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.ui_canvas'))
  }
}
