import { Course } from '../data/Models';
import { Chapter, ResourceRoute } from '../data/ResourceModels';
import { fetchChapters } from '../api/ResourceApi';
import { ApiError, ApiErrorKind } from '../api/errors';
import { SessionManager } from '../auth/SessionManager';
import { ResourceStateView } from './ResourceViews';
import { WorkListView } from './WorkListView';
import { CourseWork } from '../data/WorkModels';

@ComponentV2
export struct CourseDetailView {
  @Require @Param course: Course;
  @Event onOpenResources: (route: ResourceRoute) => void = () => {};
  @Event onRequestLogin: () => void = () => {};
  @Event onOpenWork: (work: CourseWork) => void = () => {};
  @Local private tab: number = 0;
  @Local private loading: boolean = true;
  @Local private failure: ApiErrorKind | undefined = undefined;
  @Local private chapters: Chapter[] = [];
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
    const session = SessionManager.get().snapshot();
    if (!this.active || !session.ready) return;
    const key: string = `${session.loggedIn}:${session.savedAt}`;
    if (key === this.sessionKey) return;
    this.sessionKey = key;
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const version: number = ++this.version;
    this.loading = true;
    this.failure = undefined;
    try {
      const catalog = await fetchChapters(this.course);
      if (this.active && version === this.version) this.chapters = catalog.chapters;
    } catch (error) {
      if (this.active && version === this.version) this.failure = error instanceof ApiError ? error.kind : ApiErrorKind.PARSE;
    } finally {
      if (this.active && version === this.version) this.loading = false;
    }
  }

  private resources(chapter?: Chapter): ResourceRoute {
    return { course: this.course, title: chapter?.title ?? this.course.name, chapterId: chapter?.id ?? '',
      folderId: '0', parentId: '0', enc: '' };
  }

  build() {
    Column() {
      Column({ space: $r('app.float.ui_space_content') }) {
        Text(this.course.name).fontSize($r('app.float.ui_text_card_title')).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ui_text_primary'))
        if (this.course.teacher.length > 0 || this.course.semester.length > 0) {
          Text([this.course.teacher, this.course.semester].filter((value: string) => value.length > 0).join(' · '))
            .fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
        }
        Row({ space: $r('app.float.ui_space_content') }) {
          Button($r('app.string.course_resources')).layoutWeight(1).height($r('app.float.ui_size_filter_control'))
            .fontSize($r('app.float.ui_text_body'))
            .fontColor(this.tab === 0 ? $r('app.color.ui_surface') : $r('app.color.ui_accent'))
            .backgroundColor(this.tab === 0 ? $r('app.color.ui_accent') : $r('app.color.ui_accent_soft'))
            .onClick(() => { this.tab = 0; })
          Button($r('app.string.course_work')).layoutWeight(1).height($r('app.float.ui_size_filter_control'))
            .fontSize($r('app.float.ui_text_body'))
            .fontColor(this.tab === 1 ? $r('app.color.ui_surface') : $r('app.color.ui_accent'))
            .backgroundColor(this.tab === 1 ? $r('app.color.ui_accent') : $r('app.color.ui_accent_soft'))
            .onClick(() => { this.tab = 1; })
        }.width('100%')
      }.width('100%').padding($r('app.float.ui_space_page')).alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.ui_surface'))
      if (this.tab === 1) {
        WorkListView({ course: this.course, onOpenWork: (work: CourseWork) => { this.onOpenWork(work); }, onRequestLogin: () => { this.onRequestLogin(); } }).layoutWeight(1)
      } else {
        Column() {
          Column() {
            Row() {
              Text($r('app.string.course_materials'))
                .fontSize($r('app.float.ui_text_card_title')).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ui_text_primary')).layoutWeight(1)
              Text('›').fontSize($r('app.float.ui_text_card_title')).fontColor($r('app.color.ui_text_tertiary'))
            }.width('100%').padding($r('app.float.ui_space_card'))
              .backgroundColor($r('app.color.ui_surface')).borderRadius($r('app.float.ui_radius_card'))
              .onClick(() => { this.onOpenResources(this.resources()); })
          }.width('100%')
            .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page'),
              top: $r('app.float.ui_space_page_top') })
            .margin({ bottom: $r('app.float.ui_space_list') })
          Text($r('app.string.course_chapters')).fontSize($r('app.float.ui_text_label'))
            .fontColor($r('app.color.ui_text_secondary'))
            .width('100%').textAlign(TextAlign.Start)
            .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          if (this.loading || this.failure !== undefined || this.chapters.length === 0) {
            ResourceStateView({ loading: this.loading, failure: this.failure, emptyMessage: $r('app.string.chapters_empty'),
              onRetry: () => { this.refresh(); }, onRequestLogin: () => { this.onRequestLogin(); } }).layoutWeight(1)
          } else {
          List() {
          ForEach(this.chapters, (chapter: Chapter, index: number) => {
            ListItem() {
              Row({ space: $r('app.float.ui_space_content') }) {
                Text(chapter.number).fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_accent'))
                Text(chapter.title).fontSize(chapter.group ? $r('app.float.ui_text_card_title') : $r('app.float.ui_text_body'))
                  .fontWeight(chapter.group ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor($r('app.color.ui_text_primary')).layoutWeight(1)
                if (!chapter.group) {
                  Text('›').fontSize($r('app.float.ui_text_card_title')).fontColor($r('app.color.ui_text_tertiary'))
                }
              }.width('100%').padding($r('app.float.ui_space_card'))
                .backgroundColor(chapter.group ? $r('app.color.ui_canvas') : $r('app.color.ui_surface'))
                .borderRadius($r('app.float.ui_radius_card'))
                .onClick(() => { if (!chapter.group) this.onOpenResources(this.resources(chapter)); })
            }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
              .margin({ top: index === 0 ? $r('app.float.ui_space_list') : 0,
                bottom: index === this.chapters.length - 1 ? $r('app.float.ui_space_page') : $r('app.float.ui_space_list') })
          }, (chapter: Chapter) => chapter.id)
          }.width('100%').layoutWeight(1)
          }
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.ui_canvas'))
  }
}
