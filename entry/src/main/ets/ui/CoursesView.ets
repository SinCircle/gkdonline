import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadCourses, USING_SAMPLE_DATA } from '../data/ContentSource';
import { Course, CourseCatalog, CourseSemester } from '../data/Models';
import { ApiError, ApiErrorKind } from '../api/errors';
import { filterCourses } from '../api/CourseParser';
import { SessionManager, SessionState } from '../auth/SessionManager';
import { fetchCourseWork } from '../api/WorkApi';
import { CourseWork } from '../data/WorkModels';

const DOMAIN: number = 0x0a01;
const TAG: string = 'CoursesView';

@ComponentV2
export struct PageLoading {
  @Param message: Resource = $r('app.string.courses_loading');

  build() {
    Column({ space: $r('app.float.ui_space_loading') }) {
      LoadingProgress()
        .width($r('app.float.ui_size_loading'))
        .height($r('app.float.ui_size_loading'))
        .color($r('app.color.ui_accent'))
      Text(this.message)
        .fontSize($r('app.float.ui_text_body'))
        .fontColor($r('app.color.ui_text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

@ComponentV2
export struct CoursesView {
  @Event onRequestLogin: () => void = () => {};
  @Event onOpenCourse: (course: Course) => void = () => {};
  @Local private courses: Course[] = [];
  @Local private visibleCourses: Course[] = [];
  @Local private semesterOptions: string[] = [];
  @Local private selectedIndex: number = 0;
  @Local private loading: boolean = true;
  @Local private failure: ApiErrorKind | undefined = undefined;
  @Local private unfinishedCounts: Record<string, number> = {};
  @Local private keyword: string = '';
  private filterIds: string[] = [];
  private countQueue: Course[] = [];
  private countStarted: Set<string> = new Set<string>();
  private countRunning: number = 0;
  private countBatchStartedAt: number = 0;
  private countBatchTotal: number = 0;
  private active: boolean = false;
  private requestVersion: number = 0;
  private sessionKey: string = '';
  private listener: () => void = () => {};

  aboutToAppear(): void {
    this.active = true;
    this.sessionKey = '';
    this.listener = () => { if (this.active) this.syncSession(); };
    SessionManager.get().subscribe(this.listener);
    this.syncSession();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.requestVersion++;
    SessionManager.get().unsubscribe(this.listener);
  }

  private syncSession(): void {
    const state: SessionState = SessionManager.get().snapshot();
    if (!state.ready) return;
    const key: string = `${state.loggedIn}:${state.savedAt}`;
    if (key === this.sessionKey) return;
    this.sessionKey = key;
    this.refresh();
  }

  private selectSemester(index: number): void {
    if (index < 0 || index >= this.filterIds.length) return;
    this.selectedIndex = index;
    this.applyFilter();
  }

  private semesterYearLabel(): string {
    if (this.selectedIndex === 0) return '全部';
    const year: string = /^(\d{4})/.exec(this.semesterOptions[this.selectedIndex] ?? '')?.[1] ?? '';
    return year.length === 4 ? year.slice(2) : '选择';
  }

  private semesterSeasonLabel(): string {
    if (this.selectedIndex === 0) return '学期';
    const label: string = this.semesterOptions[this.selectedIndex] ?? '';
    if (label.includes('春')) return '春期';
    if (label.includes('秋')) return '秋期';
    if (label.includes('夏')) return '夏期';
    if (label.includes('冬')) return '冬期';
    return '学期';
  }

  @Builder
  private semesterMenu() {
    Menu() {
      ForEach(this.semesterOptions, (option: string, index: number) => {
        MenuItem({ content: option })
          .height($r('app.float.ui_size_filter_control'))
          .selected(this.selectedIndex === index)
          .selectIcon(true)
          .onClick(() => { this.selectSemester(index); })
      }, (option: string, index: number) => `${index}:${option}`)
    }
  }

  // 学期与关键字一起决定列表内容；两者任一变化都走这里，避免各自维护一份过滤结果。
  private applyFilter(): void {
    const byTerm: Course[] = filterCourses(this.courses, this.filterIds[this.selectedIndex]);
    const keyword: string = this.keyword.trim().toLowerCase();
    const matched: Course[] = keyword.length === 0 ? byTerm : byTerm.filter((course: Course) =>
      course.name.toLowerCase().includes(keyword) || course.teacher.toLowerCase().includes(keyword));
    this.visibleCourses = matched;
    this.queueUnfinishedCounts(matched, this.requestVersion);
  }

  private queueUnfinishedCounts(courses: Course[], version: number): void {
    let added: number = 0;
    for (const course of courses) {
      if (!this.countStarted.has(course.id)) {
        this.countStarted.add(course.id);
        this.countQueue.push(course);
        added++;
      }
    }
    if (added > 0 && this.countBatchStartedAt === 0) this.countBatchStartedAt = Date.now();
    this.countBatchTotal += added;
    this.pumpUnfinishedCounts(version);
  }

  private pumpUnfinishedCounts(version: number): void {
    while (this.active && version === this.requestVersion && this.countRunning < 2 && this.countQueue.length > 0) {
      const course: Course = this.countQueue.shift()!;
      this.countRunning++;
      this.loadUnfinishedCount(course, version);
    }
  }

  private async loadUnfinishedCount(course: Course, version: number): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) return;
      const works: CourseWork[] = await fetchCourseWork(course, context.cacheDir);
      if (this.active && version === this.requestVersion) {
        const next: Record<string, number> = {};
        for (const key of Object.keys(this.unfinishedCounts)) next[key] = this.unfinishedCounts[key];
        next[course.id] = works.filter((work: CourseWork) => work.status.trim() === '未交').length;
        this.unfinishedCounts = next;
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, '作业数读取失败，课程 %{public}s：%{public}s', course.id, (error as Error).message);
    } finally {
      if (version === this.requestVersion) {
        this.countRunning--;
        if (this.countQueue.length === 0 && this.countRunning === 0) {
          hilog.info(DOMAIN, TAG, '作业数补齐：已请求 %{public}d 门课程，耗时 %{public}d ms',
            this.countBatchTotal, Date.now() - this.countBatchStartedAt);
          this.countBatchStartedAt = 0;
          this.countBatchTotal = 0;
        }
        this.pumpUnfinishedCounts(version);
      }
    }
  }

  private failureText(): Resource {
    switch (this.failure) {
      case ApiErrorKind.SESSION_EXPIRED: return $r('app.string.courses_login_required');
      case ApiErrorKind.NETWORK: return $r('app.string.courses_network_error');
      case ApiErrorKind.PARSE: return $r('app.string.courses_parse_error');
      default: return $r('app.string.courses_load_error');
    }
  }

  private async refresh(): Promise<void> {
    const version: number = ++this.requestVersion;
    this.loading = true;
    this.failure = undefined;
    this.unfinishedCounts = {};
    this.countQueue = [];
    this.countStarted = new Set<string>();
    this.countRunning = 0;
    this.countBatchStartedAt = 0;
    this.countBatchTotal = 0;
    if (!SessionManager.get().loggedIn) {
      this.courses = [];
      this.visibleCourses = [];
      this.failure = ApiErrorKind.SESSION_EXPIRED;
      this.loading = false;
      return;
    }
    try {
      const catalog: CourseCatalog = await loadCourses();
      if (!this.active || version !== this.requestVersion) return;
      const previous: string | undefined = this.filterIds[this.selectedIndex];
      this.courses = catalog.courses;
      const terms: CourseSemester[] = catalog.semesters.filter((term: CourseSemester) =>
        term.id === catalog.currentSemesterId || catalog.courses.some((course: Course) =>
          course.sectionId === term.id));
      const allSemesters: string = this.getUIContext().getHostContext()?.resourceManager
        .getStringSync($r('app.string.course_all_semesters')) ?? '全部学期';
      const options: string[] = [allSemesters];
      const ids: string[] = [''];
      for (const term of terms) {
        options.push(term.label);
        ids.push(term.id);
      }
      this.semesterOptions = options;
      this.filterIds = ids;
      const selected: number = ids.indexOf(previous ?? catalog.currentSemesterId);
      this.selectSemester(selected < 0 ? 0 : selected);
      hilog.info(DOMAIN, TAG, '课程加载成功：总数 %{public}d，当前筛选 %{public}s，显示 %{public}d',
        this.courses.length, this.filterIds[this.selectedIndex], this.visibleCourses.length);
    } catch (error) {
      const err: ApiError = error as ApiError;
      hilog.error(DOMAIN, TAG, '读取课程内容失败: %{public}s', err.message);
      if (this.active && version === this.requestVersion) {
        this.failure = err instanceof ApiError ? err.kind : ApiErrorKind.PARSE;
      }
    } finally {
      if (this.active && version === this.requestVersion) this.loading = false;
    }
  }

  build() {
    Column() {
      if (USING_SAMPLE_DATA && (this.loading || this.failure !== undefined || this.courses.length === 0)) {
        Text($r('app.string.sample_data_notice'))
          .fontSize($r('app.float.ui_text_label'))
          .fontColor($r('app.color.ui_text_secondary'))
          .width('100%')
          .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          .margin({ bottom: $r('app.float.ui_space_list') })
      }
      if (this.loading) {
        Column() {
          PageLoading({ message: $r('app.string.courses_loading') })
        }
        .width('100%').layoutWeight(1)
        .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
        .justifyContent(FlexAlign.Center)
      } else if (this.failure !== undefined) {
        Column({ space: $r('app.float.ui_space_section') }) {
          Text(this.failureText())
            .fontSize($r('app.float.ui_text_body'))
            .fontColor($r('app.color.ui_text_primary'))
          Button(this.failure === ApiErrorKind.SESSION_EXPIRED ? $r('app.string.login_action') :
            $r('app.string.retry_load'))
            .fontSize($r('app.float.ui_text_button'))
            .backgroundColor($r('app.color.ui_accent'))
            .onClick(() => {
              if (this.failure === ApiErrorKind.SESSION_EXPIRED) this.onRequestLogin();
              else this.refresh();
            })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
      } else {
        Column({ space: $r('app.float.ui_space_list') }) {
          Column({ space: $r('app.float.ui_space_content') }) {
            if (USING_SAMPLE_DATA) {
              Text($r('app.string.sample_data_notice'))
                .fontSize($r('app.float.ui_text_label'))
                .fontColor($r('app.color.ui_text_secondary'))
            }
              Row({ space: $r('app.float.ui_space_content') }) {
                Column() {
                  Text(this.semesterYearLabel())
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor($r('app.color.ui_text_primary'))
                  Text(this.semesterSeasonLabel())
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor($r('app.color.ui_text_primary'))
                }
                  .width($r('app.float.ui_size_filter_control'))
                  .height($r('app.float.ui_size_filter_control'))
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor($r('app.color.ui_surface'))
                  .borderRadius($r('app.float.ui_radius_button'))
                  .id('semester-trigger')
                  .accessibilityText(`选择学期：${this.semesterOptions[this.selectedIndex] ?? ''}`)
                  .bindMenu(this.semesterMenu)
                TextInput({ text: this.keyword, placeholder: $r('app.string.course_search_hint') })
                  .height($r('app.float.ui_size_filter_control'))
                  .fontSize($r('app.float.ui_text_body'))
                  .fontColor($r('app.color.ui_text_primary'))
                  .placeholderColor($r('app.color.ui_text_tertiary'))
                  .backgroundColor($r('app.color.ui_surface'))
                  .borderRadius($r('app.float.ui_radius_button'))
                  .layoutWeight(1)
                  .onChange((value: string) => { this.keyword = value; this.applyFilter(); })
              }.width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)
            .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page'),
              top: $r('app.float.ui_space_page_top') })
          List() {
          if (this.visibleCourses.length === 0) {
            ListItem() {
              Text($r('app.string.courses_empty'))
                .fontSize($r('app.float.ui_text_body'))
                .fontColor($r('app.color.ui_text_secondary'))
                .width('100%').textAlign(TextAlign.Center)
                .padding($r('app.float.ui_space_section'))
            }.margin({ bottom: $r('app.float.ui_space_page') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }
          ForEach(this.visibleCourses, (course: Course, index: number) => {
            ListItem() {
              Row() {
                Column({ space: $r('app.float.ui_space_content') }) {
                  Text(course.name)
                    .fontSize($r('app.float.ui_text_card_title'))
                    .fontColor($r('app.color.ui_text_primary'))
                    .fontWeight(FontWeight.Medium)
                  if (course.teacher.length > 0) {
                    Row() {
                    Text($r('app.string.course_teacher'))
                      .fontSize($r('app.float.ui_text_body'))
                      .fontColor($r('app.color.ui_text_secondary'))
                    Text(course.teacher)
                      .fontSize($r('app.float.ui_text_body'))
                      .fontColor($r('app.color.ui_text_secondary'))
                    }
                  }
                  if (course.semester.length > 0) {
                    Text(course.semester)
                      .fontSize($r('app.float.ui_text_label'))
                      .fontColor($r('app.color.ui_text_tertiary'))
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if ((this.unfinishedCounts[course.id] ?? 0) > 0) {
                  Text(this.unfinishedCounts[course.id].toString())
                    .fontSize($r('app.float.ui_text_label'))
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ui_surface'))
                    .backgroundColor($r('app.color.ui_error'))
                    .width($r('app.float.ui_size_badge'))
                    .height($r('app.float.ui_size_badge'))
                    .borderRadius($r('app.float.ui_size_badge'))
                    .textAlign(TextAlign.Center)
                    .accessibilityText(`${this.unfinishedCounts[course.id]} 个未完成作业`)
                }
              }
              .width('100%')
              .padding($r('app.float.ui_space_card'))
              .backgroundColor($r('app.color.ui_surface'))
              .borderRadius($r('app.float.ui_radius_card'))
              .onClick(() => { this.onOpenCourse(course); })
            }.margin({ bottom: index === this.visibleCourses.length - 1 ?
              $r('app.float.ui_space_page') : $r('app.float.ui_space_list') })
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
          }, (course: Course) => course.id)
          }.width('100%').layoutWeight(1)
        }.width('100%').layoutWeight(1)
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.ui_canvas'))
  }
}
