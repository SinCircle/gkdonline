import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadNotices, USING_SAMPLE_NOTICES as USING_SAMPLE_DATA } from '../data/ContentSource';
import { Notice } from '../data/Models';
import { PageLoading } from './CoursesView';
import { NoticeAccessError } from '../api/NoticeApi';

const DOMAIN: number = 0x0a01;
const TAG: string = 'NoticesView';

@ComponentV2
export struct NoticesView {
  @Local private notices: Notice[] = [];
  @Local private loading: boolean = true;
  @Local private failed: boolean = false;
  @Local private failureDetail: string = '';
  @Local private rejected: boolean = false;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.refresh();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.failed = false;
    this.failureDetail = '';
    this.rejected = false;
    try {
      const items: Notice[] = await loadNotices();
      if (this.active) this.notices = items;
    } catch (error) {
      const err: Error = error as Error;
      hilog.error(DOMAIN, TAG, '读取通知内容失败: %{public}s', err.message);
      if (this.active) {
        this.failed = true;
        this.rejected = error instanceof NoticeAccessError && /不被允许访问|请求出错/.test(err.message);
        if (error instanceof NoticeAccessError) {
          this.failureDetail = `HTTP ${error.status} · ${error.response}`;
        } else this.failureDetail = err.message;
      }
    } finally {
      if (this.active) this.loading = false;
    }
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
      if (this.loading) {
        Column() {
          PageLoading({ message: $r('app.string.notices_loading') })
        }
        .width('100%').layoutWeight(1)
        .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
        .justifyContent(FlexAlign.Center)
      } else if (this.failed) {
        Column({ space: $r('app.float.ui_space_section') }) {
          Text(this.rejected ? $r('app.string.notices_access_denied') : $r('app.string.notices_load_error'))
            .fontSize($r('app.float.ui_text_card_title'))
            .fontColor($r('app.color.ui_text_primary'))
          if (this.failureDetail) {
            Text(this.failureDetail)
              .fontSize($r('app.float.ui_text_body'))
              .fontColor($r('app.color.ui_text_secondary'))
              .width('100%')
          }
          Button($r('app.string.retry_load'))
            .fontSize($r('app.float.ui_text_button'))
            .backgroundColor($r('app.color.ui_surface'))
            .fontColor($r('app.color.ui_accent'))
            .onClick(() => { this.refresh(); })
        }.width('100%').layoutWeight(1).alignItems(HorizontalAlign.Start)
          .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page'),
            top: $r('app.float.ui_space_page_top') })
      } else if (this.notices.length === 0) {
        Text($r('app.string.notices_empty'))
          .fontSize($r('app.float.ui_text_body'))
          .fontColor($r('app.color.ui_text_secondary'))
          .width('100%').layoutWeight(1).textAlign(TextAlign.Center)
          .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
      } else {
        List() {
          if (USING_SAMPLE_DATA) {
            ListItem() {
              Text($r('app.string.sample_data_notice'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_secondary'))
                .width('100%')
            }.margin({ top: $r('app.float.ui_space_page_top'), bottom: $r('app.float.ui_space_list') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }
          ForEach(this.notices, (notice: Notice, index: number) => {
            ListItem() {
              Column({ space: $r('app.float.ui_space_content') }) {
                Row() {
                  Text(notice.title)
                    .fontSize($r('app.float.ui_text_card_title'))
                    .fontColor($r('app.color.ui_text_primary'))
                    .fontWeight(FontWeight.Medium)
                    .layoutWeight(1)
                  Text(notice.read ? $r('app.string.notice_read') : $r('app.string.notice_unread'))
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor(notice.read ? $r('app.color.ui_text_tertiary') :
                      $r('app.color.ui_accent'))
                }.width('100%')
                Text(notice.content)
                  .fontSize($r('app.float.ui_text_body'))
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
            }.margin({ top: !USING_SAMPLE_DATA && index === 0 ? $r('app.float.ui_space_page_top') : 0,
              bottom: index === this.notices.length - 1 ?
                $r('app.float.ui_space_page') : $r('app.float.ui_space_list') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }, (notice: Notice) => notice.id)
        }.width('100%').layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.ui_canvas'))
  }
}
