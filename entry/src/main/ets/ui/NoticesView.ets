import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadNotices, USING_SAMPLE_NOTICES as USING_SAMPLE_DATA } from '../data/ContentSource';
import { Notice } from '../data/Models';
import { PageLoading } from './CoursesView';
import { NoticeAccessError, NoticePage } from '../api/NoticeApi';
import { ApiError } from '../api/errors';
import { NoticeNavigation } from './NoticeNavigation';
import { LocalUiStore } from '../data/LocalUiStore';

const DOMAIN: number = 0x0a01;
const TAG: string = 'NoticesView';

@ComponentV2
export struct NoticesView {
  @Local private notices: Notice[] = [];
  @Local private loading: boolean = true;
  @Local private refreshing: boolean = false;
  @Local private failed: boolean = false;
  @Local private rejected: boolean = false;
  @Local private pageError: string = '';
  @Local private noticePins: Record<string, boolean> = {};
  @Local private readOverrides: Record<string, boolean> = {};
  @Local private localError: string = '';
  private localStore: LocalUiStore = LocalUiStore.get();
  private active: boolean = false;
  private nextCursor: string = '';
  private hasMore: boolean = false;
  private loadingMore: boolean = false;
  private requestVersion: number = 0;

  aboutToAppear(): void {
    this.active = true;
    try {
      this.localStore.init(this.getUIContext().getHostContext());
      this.noticePins = this.localStore.readNoticePins();
      this.readOverrides = this.localStore.readNoticeRead();
    } catch (error) { this.localError = (error as Error).message; }
    if (this.notices.length === 0) this.refresh();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.requestVersion++;
    this.refreshing = false;
  }

  private async refresh(pull: boolean = false): Promise<void> {
    const version: number = ++this.requestVersion;
    if (pull) this.refreshing = true;
    else { this.loading = true; this.failed = false; }
    this.rejected = false;
    this.pageError = '';
    this.nextCursor = '';
    this.hasMore = false;
    try {
      const page: NoticePage = await loadNotices();
      if (this.active && version === this.requestVersion) {
        this.notices = page.list;
        this.nextCursor = page.lastGetId;
        this.hasMore = !page.lastPage && !!page.lastGetId;
        this.failed = false;
      }
    } catch (error) {
      const err: Error = error as Error;
      let detail: string = err.message;
      if (error instanceof ApiError) {
        detail = `HTTP ${error.status} · ${error.detail || error.message} · ${error.responseBody.substring(0, 200)}`;
      } else if (error instanceof NoticeAccessError) {
        detail = `HTTP ${error.status} · ${error.response}`;
      }
      // 界面只给友好文案；HTTP 状态码、响应体这类细节只进日志，不摆到界面上。
      hilog.error(DOMAIN, TAG, '读取通知内容失败: %{public}s；详情 %{public}s', err.message, detail);
      if (this.active && version === this.requestVersion) {
        this.failed = true;
        this.rejected = error instanceof NoticeAccessError && /不被允许访问|请求出错/.test(err.message);
      }
    } finally {
      if (this.active && version === this.requestVersion) {
        this.loading = false;
        this.refreshing = false;
      }
    }
  }

  private async loadMore(): Promise<void> {
    if (!this.active || !this.hasMore || !this.nextCursor || this.loadingMore || this.pageError) return;
    const version: number = this.requestVersion;
    this.loadingMore = true;
    try {
      const page: NoticePage = await loadNotices(this.nextCursor);
      if (!this.active || version !== this.requestVersion) return;
      const seen: Set<string> = new Set(this.notices.map((notice: Notice) => notice.uuid));
      this.notices = this.notices.concat(page.list.filter((notice: Notice) => !seen.has(notice.uuid)));
      this.nextCursor = page.lastGetId;
      this.hasMore = !page.lastPage && !!page.lastGetId;
    } catch (error) {
      if (this.active && version === this.requestVersion) this.pageError = (error as Error).message;
    } finally { this.loadingMore = false; }
  }

  private sortedNotices(): Notice[] {
    return this.notices.filter((notice: Notice) => !!this.noticePins[notice.uuid])
      .concat(this.notices.filter((notice: Notice) => !this.noticePins[notice.uuid]));
  }

  private isRead(notice: Notice): boolean {
    return this.readOverrides[notice.uuid] !== undefined ?
      this.readOverrides[notice.uuid] : notice.read;
  }

  private pinNotice(uuid: string): void {
    try {
      const next: Record<string, boolean> = {};
      for (const key of Object.keys(this.noticePins)) next[key] = this.noticePins[key];
      next[uuid] = !this.noticePins[uuid];
      this.localStore.saveNoticePins(next);
      this.noticePins = next;
      this.localError = '';
    } catch (error) { this.localError = (error as Error).message; }
  }

  private markNotice(uuid: string, read: boolean): void {
    try {
      const next: Record<string, boolean> = {};
      for (const key of Object.keys(this.readOverrides)) next[key] = this.readOverrides[key];
      next[uuid] = read;
      this.localStore.saveNoticeRead(next);
      this.readOverrides = next;
      this.localError = '';
    } catch (error) { this.localError = (error as Error).message; }
  }

  @Builder
  private noticeSwipeMenu(notice: Notice) {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph(this.noticePins[notice.uuid] ? $r('sys.symbol.pin_slash') : $r('sys.symbol.pin_fill'))
          .fontSize(32)
          .fontColor([$r('app.color.ui_accent')])
      }
        .width(48).height(48).padding(0)
        .backgroundColor($r('app.color.ui_surface'))
        .borderRadius($r('app.float.ui_radius_button'))
        .accessibilityText(this.noticePins[notice.uuid] ? '取消置顶这条通知' : '置顶这条通知')
        .onClick(() => { this.pinNotice(notice.uuid); })
      Button() {
        SymbolGlyph(this.isRead(notice) ? $r('sys.symbol.envelope_badge_dot') :
          $r('sys.symbol.checkmark_message'))
          .fontSize(32)
          .fontColor([this.isRead(notice) ? $r('app.color.ui_accent') :
            $r('app.color.ui_text_secondary')])
      }
        .width(48).height(48).padding(0)
        .backgroundColor($r('app.color.ui_surface'))
        .borderRadius($r('app.float.ui_radius_button'))
        .accessibilityText(this.isRead(notice) ? '标记为未读' : '标记为已读')
        .onClick(() => { this.markNotice(notice.uuid, !this.isRead(notice)); })
    }.padding({ left: $r('app.float.ui_space_page'), right: 4 })
  }

  build() {
    Column() {
      if (USING_SAMPLE_DATA && (this.loading || this.failed || this.notices.length === 0)) {
        Text($r('app.string.sample_data_notice'))
          .fontSize($r('app.float.ui_text_label'))
          .fontColor($r('app.color.ui_text_secondary'))
          .width('100%')
          .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          .margin({ bottom: $r('app.float.ui_space_list') })
      }
      Refresh({ refreshing: $$this.refreshing }) {
        List() {
          if (this.loading || this.failed || this.notices.length === 0) {
            ListItem() {
              Column({ space: $r('app.float.ui_space_section') }) {
                if (this.loading) {
                  PageLoading({ message: $r('app.string.notices_loading') })
                } else if (this.failed) {
                  Text(this.rejected ? $r('app.string.notices_access_denied') : $r('app.string.notices_load_error'))
                    .fontSize($r('app.float.ui_text_card_title'))
                    .fontColor($r('app.color.ui_text_primary'))
                } else {
                  Text($r('app.string.notices_empty'))
                    .fontSize($r('app.float.ui_text_body'))
                    .fontColor($r('app.color.ui_text_secondary'))
                }
              }.width('100%').height('100%').justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .padding($r('app.float.ui_space_page'))
            }.height('100%').id('notices-state-row')
          } else {
          if (this.localError) {
            ListItem() {
              Text(this.localError)
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_error'))
                .padding($r('app.float.ui_space_page'))
            }
          }
          if (USING_SAMPLE_DATA) {
            ListItem() {
              Text($r('app.string.sample_data_notice'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_secondary'))
                .width('100%')
            }.margin({ top: $r('app.float.ui_space_page_top'), bottom: $r('app.float.ui_space_list') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }
          ForEach(this.sortedNotices(), (notice: Notice, index: number) => {
            ListItem() {
              Column({ space: $r('app.float.ui_space_content') }) {
                Row() {
                  Text(notice.title)
                    .fontSize($r('app.float.ui_text_card_title'))
                    .fontColor($r('app.color.ui_text_primary'))
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)
                  if (this.noticePins[notice.uuid]) {
                    SymbolGlyph($r('sys.symbol.pin_fill'))
                      .fontSize(16)
                      .fontColor([$r('app.color.ui_text_tertiary')])
                      .margin({ right: 8 })
                      .id('notice-pin-' + notice.uuid)
                      .accessibilityText('已置顶')
                  }
                  Text(this.isRead(notice) ? $r('app.string.notice_read') : $r('app.string.notice_unread'))
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor(this.isRead(notice) ? $r('app.color.ui_text_tertiary') :
                      $r('app.color.ui_accent'))
                }.width('100%')
                Text(notice.content)
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_secondary'))
                  .width('100%')
                Text(notice.sender)
                  .fontSize($r('app.float.ui_text_label'))
                  .fontColor($r('app.color.ui_text_secondary'))
                  .width('100%')
                Text(notice.time)
                  .fontSize($r('app.float.ui_text_label'))
                  .fontColor($r('app.color.ui_text_tertiary'))
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding($r('app.float.ui_space_card'))
              .backgroundColor($r('app.color.ui_surface'))
              .borderRadius($r('app.float.ui_radius_card'))
            }.id('notice-row-' + notice.uuid)
              .onClick(() => { NoticeNavigation.get().open(notice); })
              .margin({ top: !USING_SAMPLE_DATA && index === 0 ? $r('app.float.ui_space_page_top') : 0,
              bottom: index === this.notices.length - 1 ?
                $r('app.float.ui_space_page') : $r('app.float.ui_space_list') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
              .swipeAction({ end: { builder: () => { this.noticeSwipeMenu(notice); } },
                edgeEffect: SwipeEdgeEffect.Spring })
          }, (notice: Notice) => notice.uuid)
          if (this.pageError) {
            ListItem() {
              Text($r('app.string.notices_more_failed'))
                .fontSize($r('app.float.ui_text_body'))
                .fontColor($r('app.color.ui_accent'))
                .width('100%').textAlign(TextAlign.Center)
                .onClick(() => { this.pageError = ''; this.loadMore(); })
            }.width('100%').padding($r('app.float.ui_space_page'))
          }
          ListItem() {
            Column() {}.height($r('app.float.ui_space_floating_bar'))
          }.id('notices-floating-bar-spacer')
          }
        }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .onReachEnd(() => { this.loadMore(); })
      }.width('100%').layoutWeight(1).onRefreshing(() => {
        hilog.info(0x0a01, 'PullRefresh', 'notices');
        this.refresh(true);
      })
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.ui_canvas'))
  }
}
