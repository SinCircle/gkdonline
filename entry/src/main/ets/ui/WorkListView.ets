import { Course } from '../data/Models';
import { CourseWork } from '../data/WorkModels';
import { fetchCourseWork } from '../api/WorkApi';
import { ApiError, ApiErrorKind } from '../api/errors';
import { SessionManager } from '../auth/SessionManager';
import { common } from '@kit.AbilityKit';
import { remindDueWorks, ReminderResult } from '../api/WorkReminder';
import { ResourceStateView } from './ResourceViews';

@ComponentV2
export struct WorkListView {
  @Require @Param course: Course;
  @Event onRequestLogin: () => void = () => {};
  @Event onOpenWork: (work: CourseWork) => void = () => {};
  @Local private loading: boolean = true;
  @Local private failure: ApiErrorKind | undefined = undefined;
  @Local private items: CourseWork[] = [];
  @Local private reminderMessage: string = '';
  private active: boolean = false;
  private version: number = 0;
  private sessionKey: string = '';
  private listener: () => void = () => {};

  aboutToAppear(): void {
    this.active = true;
    this.listener = () => { this.syncSession(); };
    SessionManager.get().subscribe(this.listener);
    this.syncSession();
  }
  aboutToDisappear(): void {
    this.active = false;
    this.version++;
    SessionManager.get().unsubscribe(this.listener);
  }
  private syncSession(): void {
    const state = SessionManager.get().snapshot();
    if (!this.active || !state.ready) return;
    const key: string = `${state.loggedIn}:${state.savedAt}`;
    if (key === this.sessionKey) return;
    this.sessionKey = key;
    this.refresh();
  }
  private async refresh(): Promise<void> {
    const version: number = ++this.version;
    this.loading = true;
    this.failure = undefined;
    this.reminderMessage = '';
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('无法取得缓存目录');
      const items: CourseWork[] = await fetchCourseWork(this.course, context.cacheDir);
      if (this.active && version === this.version) {
        this.items = items;
        this.checkReminders(items, version);
      }
    } catch (error) {
      if (this.active && version === this.version) this.failure = error instanceof ApiError ? error.kind : ApiErrorKind.NETWORK;
    } finally { if (this.active && version === this.version) this.loading = false; }
  }
  private async checkReminders(items: CourseWork[], version: number): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) throw new Error('无法取得应用目录');
      const result: ReminderResult = await remindDueWorks(this.course, items, context);
      if (this.active && version === this.version && result.sent > 0) {
        this.reminderMessage = `已发送 ${result.sent} 条本地作业截止提醒` +
          (result.active > 0 ? ` · 通知中心已确认 ${result.active} 条` : '');
      }
    } catch (error) {
      if (this.active && version === this.version) this.reminderMessage = `本地提醒未发送：${(error as Error).message}`;
    }
  }
  /** 已完成/待批阅无需再动作，用次级文字色弱化；未交等仍需处理的状态保持强调色。 */
  private statusColor(status: string): Resource {
    return /已完成|待批阅/.test(status) ? $r('app.color.ui_text_secondary') : $r('app.color.ui_accent');
  }
  build() {
    Column() {
      if (this.loading || this.failure !== undefined || this.items.length === 0) {
        ResourceStateView({ loading: this.loading, failure: this.failure, emptyMessage: $r('app.string.work_empty'), work: true,
          onRetry: () => { this.refresh(); }, onRequestLogin: () => { this.onRequestLogin(); } })
      } else {
        List() {
          ListItem() {
            Column({ space: $r('app.float.ui_space_content') }) {
              Row() {
                Text($r('app.string.work_list_scope')).fontSize($r('app.float.ui_text_label')).layoutWeight(1)
                  .fontColor($r('app.color.ui_text_secondary'))
              }.width('100%')
              if (this.reminderMessage) {
                Text(this.reminderMessage).fontSize($r('app.float.ui_text_label'))
                  .fontColor($r('app.color.ui_text_secondary')).width('100%')
              }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
            .margin({ top: $r('app.float.ui_space_page_top'), bottom: $r('app.float.ui_space_list') })
          ForEach(this.items, (item: CourseWork, index: number) => {
            ListItem() {
              Column({ space: $r('app.float.ui_space_content') }) {
                Text(item.title).fontSize($r('app.float.ui_text_card_title')).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ui_text_primary'))
                Text(item.status).fontSize($r('app.float.ui_text_body')).fontColor(this.statusColor(item.status))
                if (item.deadlineText.length > 0) {
                  Text(item.deadlineText).fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
                }
              }.width('100%').padding($r('app.float.ui_space_card')).alignItems(HorizontalAlign.Start)
                .backgroundColor($r('app.color.ui_surface')).borderRadius($r('app.float.ui_radius_card'))
                .onClick(() => { this.onOpenWork(item); })
            }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
              .margin({ bottom: index === this.items.length - 1 ? $r('app.float.ui_space_page') : $r('app.float.ui_space_list') })
          }, (item: CourseWork) => item.id)
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.ui_canvas'))
  }
}
