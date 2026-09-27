import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionManager, SessionState } from '../auth/SessionManager';
import { LoginView } from '../ui/LoginView';
import { HomeView } from '../ui/HomeView';
import { MineSettingsNavigation } from '../ui/MineView';
import { SettingsView } from '../ui/SettingsView';
import { PageLoading } from '../ui/CoursesView';
import { Course, Notice } from '../data/Models';
import { ResourceRoute } from '../data/ResourceModels';
import { CourseDetailView } from '../ui/CourseDetailView';
import { ResourceListView } from '../ui/ResourceViews';
import { CourseWork } from '../data/WorkModels';
import { WorkDetailView } from '../ui/WorkDetailView';
import { PendingWorkLink, WorkDetailRoute, WorkNavigation } from '../data/WorkNavigation';
import { NoticeNavigation } from '../ui/NoticeNavigation';
import { NoticeDetailView } from '../ui/NoticeDetailView';
import { NoticeWorkRoute, NoticeWorkWebView } from '../ui/NoticeWorkWebView';
import { CourseNotesNavigation } from '../data/LocalUiStore';
import { CourseNotesView } from '../ui/CourseNotesView';

const DOMAIN: number = 0x0a01;
const TAG: string = 'Index';

@Entry
@ComponentV2
struct Index {
  private session: SessionManager = SessionManager.get();
  private listener: () => void = () => {};
  private linkListener: () => void = () => {};
  private noticeListener: (notice: Notice) => void = () => {};
  private stack: NavPathStack = new NavPathStack();
  @Local private ready: boolean = false;
  @Local private loggedIn: boolean = false;
  @Local private selectedTabIndex: number = 0;

  private syncSession(): void {
    const state: SessionState = this.session.snapshot();
    this.ready = state.ready;
    this.loggedIn = state.loggedIn;
    hilog.info(DOMAIN, TAG, '会话通知已同步，ready=%{public}s，localCredentials=%{public}s',
      String(state.ready), String(state.loggedIn));
    if (state.ready) this.openPendingWork();
  }

  private openPendingWork(): void {
    const link: PendingWorkLink | undefined = WorkNavigation.get().peekLink();
    if (!link) return;
    const work: CourseWork = { id: link.workId, title: link.title, detailUrl: link.detailUrl,
      status: '', deadlineText: '' };
    const route: WorkDetailRoute = { work: work, courseId: link.courseId, classId: link.classId };
    this.selectedTabIndex = 0;
    this.stack.pushPathByName('WorkDetail', route);
    WorkNavigation.get().clearLink();
    hilog.info(DOMAIN, TAG, '打开作业通知：作业 %{public}s，课程 %{public}s', link.workId, link.courseId);
  }

  aboutToAppear(): void {
    MineSettingsNavigation.open = () => { this.stack.pushPathByName('Settings', null); };
    CourseNotesNavigation.open = (course: Course) => { this.stack.pushPathByName('CourseNotes', course); };
    this.listener = () => { this.syncSession(); };
    this.session.subscribe(this.listener);
    this.linkListener = () => { if (this.ready) this.openPendingWork(); };
    WorkNavigation.get().subscribeLink(this.linkListener);
    this.noticeListener = (notice: Notice) => { this.stack.pushPathByName('NoticeDetail', notice); };
    NoticeNavigation.get().subscribe(this.noticeListener);
    this.syncSession();
    this.session.init();
  }

  aboutToDisappear(): void {
    MineSettingsNavigation.open = () => {};
    CourseNotesNavigation.open = () => {};
    this.session.unsubscribe(this.listener);
    WorkNavigation.get().unsubscribeLink(this.linkListener);
    NoticeNavigation.get().unsubscribe(this.noticeListener);
  }

  @Builder
  destinations(name: string, param: Object) {
    if (name === 'CourseNotes') {
      NavDestination() {
        CourseNotesView({ course: param as Course })
      }.title('备注').hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    } else if (name === 'Settings') {
      NavDestination() {
        SettingsView()
      }.title($r('app.string.settings_title'))
    } else if (name === 'Login') {
      NavDestination() {
        LoginView({
          onLoggedIn: () => {
            this.syncSession();
            this.stack.pop();
          },
          onBack: () => { this.stack.pop(); },
        })
      }.title($r('app.string.login_title'))
        .hideBackButton(false)
        .onBackPressed((): boolean => {
          this.stack.pop();
          return true;
        })
    } else if (name === 'CourseDetail') {
      NavDestination() {
        CourseDetailView({ course: param as Course,
          onOpenWork: (work: CourseWork) => {
            const course: Course = param as Course;
            this.stack.pushPathByName('WorkDetail', { work: work, course: course } as WorkDetailRoute);
          },
          onOpenResources: (route: ResourceRoute) => { this.stack.pushPathByName('CourseResources', route); },
          onRequestLogin: () => { this.stack.pushPathByName('Login', null); } })
      }.title($r('app.string.course_detail')).hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    } else if (name === 'CourseResources') {
      NavDestination() {
        ResourceListView({ route: param as ResourceRoute,
          onOpenWork: (work: CourseWork) => {
            this.stack.pushPathByName('WorkDetail', { work: work, course: (param as ResourceRoute).course } as WorkDetailRoute);
          },
          onOpenFolder: (route: ResourceRoute) => { this.stack.pushPathByName('CourseResources', route); },
          onRequestLogin: () => { this.stack.pushPathByName('Login', null); } })
      }.title((param as ResourceRoute).title).hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    } else if (name === 'WorkDetail') {
      NavDestination() {
        WorkDetailView({ work: (param as WorkDetailRoute).work,
          courseId: (param as WorkDetailRoute).course?.courseId ?? (param as WorkDetailRoute).courseId ?? '',
          classId: (param as WorkDetailRoute).course?.classId ?? (param as WorkDetailRoute).classId ?? '',
          onRequestLogin: () => { this.stack.pushPathByName('Login', null); } })
      }.title('作业详情').hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    } else if (name === 'NoticeDetail') {
      NavDestination() {
        NoticeDetailView({ notice: param as Notice,
          onOpenWork: (url: string, workId: string) => {
            const route: NoticeWorkRoute = { url: url, workId: workId };
            this.stack.pushPathByName('NoticeWorkWeb', route);
          },
          onOpenWorkNative: (route: WorkDetailRoute) => { this.stack.pushPathByName('WorkDetail', route); },
          onRequestLogin: () => { this.stack.pushPathByName('Login', null); } })
      }.title($r('app.string.notice_detail')).hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    } else if (name === 'NoticeWorkWeb') {
      NavDestination() {
        NoticeWorkWebView({ url: (param as NoticeWorkRoute).url, workId: (param as NoticeWorkRoute).workId })
      }.title($r('app.string.notice_open_work')).hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    }
  }

  build() {
    Stack() {
      Navigation(this.stack) {
        HomeView({
          selectedTabIndex: this.selectedTabIndex,
          onTabChange: (index: number) => { this.selectedTabIndex = index; },
          onRequestLogin: () => { this.stack.pushPathByName('Login', null); },
          onOpenCourse: (course: Course) => { this.stack.pushPathByName('CourseDetail', course); },
        })
      }
      .title(this.selectedTabIndex === 0 ? $r('app.string.tab_courses') :
        this.selectedTabIndex === 1 ? $r('app.string.tab_notices') : $r('app.string.tab_mine'))
      .titleMode(NavigationTitleMode.Mini)
      .hideBackButton(true)
      .navDestination(this.destinations)
      .mode(NavigationMode.Stack)
      .width('100%').height('100%')
      if (!this.ready) {
        Column() {
          PageLoading({ message: $r('app.string.loading_session') })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.ui_canvas'))
      }
    }
    .width('100%').height('100%')
  }
}
