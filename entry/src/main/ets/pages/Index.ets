import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionManager, SessionState } from '../auth/SessionManager';
import { LoginView } from '../ui/LoginView';
import { HomeView } from '../ui/HomeView';
import { PageLoading } from '../ui/CoursesView';
import { Course } from '../data/Models';
import { ResourceRoute } from '../data/ResourceModels';
import { CourseDetailView } from '../ui/CourseDetailView';
import { ResourceListView } from '../ui/ResourceViews';
import { CourseWork } from '../data/WorkModels';
import { WorkDetailView } from '../ui/WorkDetailView';

const DOMAIN: number = 0x0a01;
const TAG: string = 'Index';

@Entry
@ComponentV2
struct Index {
  private session: SessionManager = SessionManager.get();
  private listener: () => void = () => {};
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
  }

  aboutToAppear(): void {
    this.listener = () => { this.syncSession(); };
    this.session.subscribe(this.listener);
    this.syncSession();
    this.session.init();
  }

  aboutToDisappear(): void {
    this.session.unsubscribe(this.listener);
  }

  @Builder
  destinations(name: string, param: Object) {
    if (name === 'Login') {
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
          onOpenWork: (work: CourseWork) => { this.stack.pushPathByName('WorkDetail', work); },
          onOpenResources: (route: ResourceRoute) => { this.stack.pushPathByName('CourseResources', route); },
          onRequestLogin: () => { this.stack.pushPathByName('Login', null); } })
      }.title($r('app.string.course_detail')).hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    } else if (name === 'CourseResources') {
      NavDestination() {
        ResourceListView({ route: param as ResourceRoute,
          onOpenWork: (work: CourseWork) => { this.stack.pushPathByName('WorkDetail', work); },
          onOpenFolder: (route: ResourceRoute) => { this.stack.pushPathByName('CourseResources', route); },
          onRequestLogin: () => { this.stack.pushPathByName('Login', null); } })
      }.title((param as ResourceRoute).title).hideBackButton(false)
        .onBackPressed((): boolean => { this.stack.pop(); return true; })
    } else if (name === 'WorkDetail') {
      NavDestination() {
        WorkDetailView({ work: param as CourseWork, onRequestLogin: () => { this.stack.pushPathByName('Login', null); } })
      }.title('作业详情').hideBackButton(false)
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
