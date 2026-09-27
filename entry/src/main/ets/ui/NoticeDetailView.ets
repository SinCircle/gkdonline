import { hilog } from '@kit.PerformanceAnalysisKit';
import { Course, CourseCatalog, Notice } from '../data/Models';
import { CourseWork } from '../data/WorkModels';
import { fetchNoticeDetail } from '../api/NoticeApi';
import { fetchCourseWork } from '../api/WorkApi';
import { loadCourses } from '../data/ContentSource';
import { ApiError, ApiErrorKind } from '../api/errors';
import { queryParam, toHttpsForCampus } from '../common/UrlUtil';
import { WorkDetailRoute } from '../data/WorkNavigation';
import { PageLoading } from './CoursesView';

const DOMAIN: number = 0x0a01;
const TAG: string = 'NoticeDetail';

@ComponentV2
export struct NoticeDetailView {
  @Param notice: Notice = { id: '', uuid: '', title: '', content: '', time: '', sender: '',
    read: false, bodyText: '', workUrl: '' };
  @Event onOpenWork: (url: string, workId: string) => void = () => {};
  @Event onOpenWorkNative: (route: WorkDetailRoute) => void = () => {};
  @Event onRequestLogin: () => void = () => {};
  @Local private detail: Notice | undefined = undefined;
  @Local private loading: boolean = true;
  @Local private failure: string = '';
  @Local private opening: boolean = false;
  @Local private workFailure: string = '';
  @Local private workLoginRequired: boolean = false;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.refresh();
  }

  aboutToDisappear(): void { this.active = false; }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.failure = '';
    try {
      const detail: Notice = await fetchNoticeDetail(this.notice.uuid);
      if (this.active) this.detail = detail;
    } catch (error) {
      if (this.active) this.failure = (error as Error).message;
    } finally { if (this.active) this.loading = false; }
  }

  /**
   * 把通知里的作业映射到我们自己的作业通道（课程 → 作业 tab → 那一条作业）。
   *
   * 通知附件入口是 PC 那套 `intoexamorwork`，服务端会跳到 PC 版作业列表，
   * 那条路原生取不到内容（实测第二个 URL 只回一张「温馨提示…[3004]」）；
   * 而我们自己的作业 tab 走 `/mooc-ans/mooc2/work/list`，一直能用。
   * 命中不了就返回 undefined，由调用方回退浏览器。
   */
  private async nativeRoute(courseId: string, classId: string, workId: string,
    cacheDir: string): Promise<WorkDetailRoute | undefined> {
    if (courseId.length === 0 || workId.length === 0) {
      hilog.warn(DOMAIN, TAG, '通知入口缺 courseId/workId（courseId=%{public}s，workId=%{public}s），不试原生',
        courseId.length > 0 ? courseId : '无', workId.length > 0 ? workId : '无');
      return undefined;
    }
    const catalog: CourseCatalog = await loadCourses();
    const course: Course | undefined =
      catalog.courses.find((item: Course) => item.courseId === courseId && (!classId || item.classId === classId)) ??
      catalog.courses.find((item: Course) => item.courseId === courseId);
    if (!course) {
      hilog.warn(DOMAIN, TAG, '课程目录 %{public}d 门里没有 courseId %{public}s，不试原生',
        catalog.courses.length, courseId);
      return undefined;
    }
    const items: CourseWork[] = await fetchCourseWork(course, cacheDir);
    const work: CourseWork | undefined = items.find((item: CourseWork) => item.id === workId);
    if (!work) {
      hilog.warn(DOMAIN, TAG, '课程「%{public}s」作业列表 %{public}d 条里没有 workId %{public}s，不试原生',
        course.name, items.length, workId);
      return undefined;
    }
    hilog.info(DOMAIN, TAG, '通知作业命中原生通道：课程「%{public}s」，作业「%{public}s」（状态 %{public}s），走原生',
      course.name, work.title, work.status);
    return { work: work, course: course, courseId: course.courseId, classId: course.classId };
  }

  /**
   * 首选我们自己的原生作业页；映射不到（缺 id、课程目录没有、作业列表里没有）才回退应用内浏览器
   * （浏览器带会话并精确跳到那一条作业）。会话失效时不进浏览器，直接说要重新登录。
   */
  private async openWork(): Promise<void> {
    const detail: Notice | undefined = this.detail;
    if (this.opening || !detail) return;
    const url: string = toHttpsForCampus(detail.workUrl);
    if (url.length === 0) { this.workFailure = '这条通知没有可直接打开的作业地址'; return; }
    const courseId: string = queryParam(url, 'courseId');
    const classId: string = queryParam(url, 'classId');
    const workId: string = queryParam(url, 'taskrefId');
    this.opening = true; this.workFailure = ''; this.workLoginRequired = false;
    hilog.info(DOMAIN, TAG, '打开通知作业：入口 %{public}s，courseId %{public}s，classId %{public}s，workId %{public}s',
      /^https:\/\//i.test(url) ? 'https' : '非 https', courseId.length > 0 ? courseId : '无',
      classId.length > 0 ? classId : '无', workId.length > 0 ? workId : '无');
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new ApiError(ApiErrorKind.PARSE, '无法取得页面缓存目录');
      const route: WorkDetailRoute | undefined = await this.nativeRoute(courseId, classId, workId, context.cacheDir);
      if (!this.active) return;
      if (route) {
        this.onOpenWorkNative(route);
        return;
      }
      hilog.info(DOMAIN, TAG, '原生通道未命中，回退应用内浏览器（会精确跳到 workId %{public}s）',
        workId.length > 0 ? workId : '无');
      this.onOpenWork(url, workId);
    } catch (error) {
      if (!this.active) return;
      if (error instanceof ApiError && error.kind === ApiErrorKind.SESSION_EXPIRED) {
        this.workLoginRequired = true;
        this.workFailure = '登录状态已失效，请重新登录后再查看作业';
        hilog.warn(DOMAIN, TAG, '作业入口要求重新登录，未打开浏览器');
      } else {
        hilog.warn(DOMAIN, TAG, '原生作业页不可用（%{public}s），回退应用内浏览器', (error as Error).message);
        this.onOpenWork(url, workId);
      }
    } finally { if (this.active) this.opening = false; }
  }

  build() {
    Column() {
      if (this.loading) {
        PageLoading({ message: $r('app.string.notices_loading') })
          .width('100%').layoutWeight(1)
      } else if (this.failure) {
        Column({ space: $r('app.float.ui_space_section') }) {
          Text(this.failure).fontSize($r('app.float.ui_text_body'))
          Button($r('app.string.retry_load')).onClick(() => { this.refresh(); })
        }.width('100%').layoutWeight(1).padding($r('app.float.ui_space_page'))
      } else if (this.detail) {
        Scroll() {
          Column({ space: $r('app.float.ui_space_section') }) {
            Text(this.detail.title)
              .fontSize($r('app.float.ui_text_page_title'))
              .fontWeight(FontWeight.Medium)
              .width('100%').id('notice-detail-title')
            Text(this.detail.sender)
              .fontSize($r('app.float.ui_text_body'))
              .fontColor($r('app.color.ui_text_secondary'))
              .width('100%').id('notice-detail-sender')
            Text(this.detail.time)
              .fontSize($r('app.float.ui_text_label'))
              .fontColor($r('app.color.ui_text_tertiary'))
              .width('100%').id('notice-detail-time')
            Text(this.detail.bodyText)
              .fontSize($r('app.float.ui_text_body'))
              .fontColor($r('app.color.ui_text_primary'))
              .width('100%').id('notice-detail-body')
            if (this.detail.workUrl) {
              Button(this.opening ? $r('app.string.notice_opening_work') : $r('app.string.notice_open_work'))
                .width('100%').height($r('app.float.ui_size_primary_button'))
                .backgroundColor($r('app.color.ui_accent'))
                .fontColor(Color.White)
                .enabled(!this.opening)
                .onClick(() => { this.openWork(); })
                .id('notice-open-work')
            }
            if (this.workFailure) {
              Text(this.workFailure)
                .fontSize($r('app.float.ui_text_body'))
                .fontColor($r('app.color.ui_error'))
                .width('100%').id('notice-work-failure')
              if (this.workLoginRequired) {
                Button($r('app.string.login_action'))
                  .width('100%').height($r('app.float.ui_size_primary_button'))
                  .backgroundColor($r('app.color.ui_accent')).fontColor(Color.White)
                  .onClick(() => { this.onRequestLogin(); })
                  .id('notice-work-login')
              }
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding($r('app.float.ui_space_page'))
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.ui_canvas'))
  }
}
