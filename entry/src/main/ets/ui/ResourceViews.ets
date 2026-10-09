import { ApiError, ApiErrorKind } from '../api/errors';
import { fetchChapterResources, fetchCourseResources } from '../api/ResourceApi';
import { CourseResource, ResourcePage, ResourceRoute } from '../data/ResourceModels';
import { SessionManager } from '../auth/SessionManager';
import { PageLoading } from './CoursesView';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { downloadResource } from '../api/ResourceDownload';
import { cachedResource } from '../api/ResourceCache';
import { ResourceTypeIcon } from './ResourceTypeIcon';
import { shareResource } from './ResourceShare';
import { CourseWork } from '../data/WorkModels';
import { formatSizeLabel } from '../common/FormatSize';
import { hilog } from '@kit.PerformanceAnalysisKit';

@ObservedV2
class ResourceRow {
  @Trace item: CourseResource;
  @Trace downloaded: boolean = false;
  @Trace busy: boolean = false;
  @Trace bytes: number = 0;
  @Trace total: number = 0;
  @Trace error: string = '';

  constructor(item: CourseResource) { this.item = item; }
}

@ComponentV2
struct ResourceDownloadStatus {
  @Require @Param row: ResourceRow;

  build() {
    Row() {
      if (this.row.busy) {
        Progress({ value: this.row.total > 0 ? this.row.bytes : 0,
          total: this.row.total > 0 ? this.row.total : 100, type: ProgressType.Ring })
          .width($r('app.float.ui_space_section')).height($r('app.float.ui_space_section'))
          .color($r('app.color.ui_accent'))
          .style({ strokeWidth: 2,
            status: this.row.total > 0 ? ProgressStatus.PROGRESSING : ProgressStatus.LOADING })
          .accessibilityText(this.row.total > 0 ?
            `下载进度 ${Math.floor(this.row.bytes * 100 / this.row.total)}%` : '正在下载')
          .id('download-progress-' + this.row.item.id)
      } else if (this.row.error.length > 0) {
        Text('重试').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_error'))
          .id('download-retry-' + this.row.item.id)
      } else if (this.row.downloaded) {
        Text('已下载').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
          .id('downloaded-' + this.row.item.id)
      }
    }.width(56).height($r('app.float.ui_space_section'))
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct ResourceStateView {
  @Param loading: boolean = false;
  @Param failure: ApiErrorKind | undefined = undefined;
  @Param emptyMessage: Resource = $r('app.string.resources_empty');
  @Param work: boolean = false;
  @Event onRequestLogin: () => void = () => {};

  private message(): Resource {
    if (this.work) {
      switch (this.failure) {
        case ApiErrorKind.SESSION_EXPIRED: return $r('app.string.work_login_required');
        case ApiErrorKind.NETWORK: return $r('app.string.work_network_error');
        case ApiErrorKind.PARSE: return $r('app.string.work_parse_error');
        default: return $r('app.string.work_load_error');
      }
    }
    switch (this.failure) {
      case ApiErrorKind.SESSION_EXPIRED: return $r('app.string.resources_login_required');
      case ApiErrorKind.NETWORK: return $r('app.string.resources_network_error');
      case ApiErrorKind.PARSE: return $r('app.string.resources_parse_error');
      default: return $r('app.string.resources_load_error');
    }
  }

  build() {
    Column({ space: $r('app.float.ui_space_section') }) {
      if (this.loading) {
        PageLoading({ message: this.work ? $r('app.string.work_loading') : $r('app.string.resources_loading') })
      } else {
        Text(this.failure === undefined ? this.emptyMessage : this.message())
          .fontSize($r('app.float.ui_text_body'))
          .fontColor($r('app.color.ui_text_secondary'))
          .textAlign(TextAlign.Center)
        if (this.failure === ApiErrorKind.SESSION_EXPIRED) {
          Button($r('app.string.login_action'))
            .fontSize($r('app.float.ui_text_button'))
            .backgroundColor($r('app.color.ui_accent'))
            .fontColor($r('app.color.ui_text_on_strong'))
            .onClick(() => { this.onRequestLogin(); })
        }
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding($r('app.float.ui_space_page'))
  }
}

@ComponentV2
export struct ResourceListView {
  @Require @Param route: ResourceRoute;
  @Event onOpenFolder: (route: ResourceRoute) => void = () => {};
  @Event onRequestLogin: () => void = () => {};
  @Event onOpenWork: (work: CourseWork) => void = () => {};
  @Local private loading: boolean = true;
  @Local private refreshing: boolean = false;
  @Local private failure: ApiErrorKind | undefined = undefined;
  @Local private items: CourseResource[] = [];
  @Local private downloading: boolean = false;
  @Local private selectedFile: CourseResource | undefined = undefined;
  @Local private downloadedPath: string = '';
  @Local private downloadedBytes: number = 0;
  @Local private rows: ResourceRow[] = [];
  private visible: boolean = false;
  private enc: string = '';
  private active: boolean = false;
  private version: number = 0;
  private sessionKey: string = '';
  private listener: () => void = () => {};
  private received: number = 0;
  private total: number = 0;
  private downloadError: string = '';

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

  private async refresh(pull: boolean = false): Promise<void> {
    const version: number = ++this.version;
    if (pull) this.refreshing = true;
    else { this.loading = true; this.failure = undefined; }
    try {
      const page: ResourcePage = this.route.chapterId.length > 0 ?
        await fetchChapterResources(this.route) : await fetchCourseResources(this.route);
      if (!this.active || version !== this.version) return;
      this.items = page.items;
      this.enc = page.enc;
      this.failure = undefined;
      this.refreshDownloaded();
    } catch (error) {
      if (this.active && version === this.version) {
        this.failure = error instanceof ApiError ? error.kind : ApiErrorKind.PARSE;
      }
    } finally {
      if (this.active && version === this.version) { this.loading = false; this.refreshing = false; }
    }
  }

  private open(item: CourseResource): void {
    if (item.work) { this.onOpenWork(item.work); return; }
    if (!item.folder) { this.download(item); return; }
    this.onOpenFolder({ course: this.route.course, title: item.name, chapterId: '',
      folderId: item.id, parentId: this.route.folderId, enc: this.enc });
  }

  private refreshDownloaded(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const previous: ResourceRow[] = this.rows;
    this.rows = this.items.map((item: CourseResource): ResourceRow => {
      const selected: boolean = this.selectedFile?.id === item.id;
      const row: ResourceRow = previous.find((candidate: ResourceRow) => candidate.item.id === item.id) ??
        new ResourceRow(item);
      row.item = item;
      row.downloaded = cachedResource(item, context.filesDir) !== undefined;
      row.busy = selected && this.downloading;
      row.bytes = selected ? this.received : 0;
      row.total = selected ? this.total : 0;
      row.error = selected ? this.downloadError : '';
      return row;
    });
  }

  private async download(item: CourseResource): Promise<void> {
    if (this.downloading) return;
    this.selectedFile = item;
    this.downloadedPath = '';
    this.downloading = true;
    this.received = 0; this.total = 0; this.downloadError = ''; this.refreshDownloaded();
    let lastUpdate: number = 0;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) throw new Error('无法取得文件目录');
      const result = await downloadResource(item, context.filesDir, (bytes: number, total?: number) => {
        if (this.active && Date.now() - lastUpdate >= 80) {
          lastUpdate = Date.now();
          this.received = bytes; this.total = total && bytes <= total ? total : 0;
          const row: ResourceRow | undefined = this.rows.find((candidate: ResourceRow) => candidate.item.id === item.id);
          if (row) { row.bytes = this.received; row.total = this.total; }
        }
      });
      if (!this.active) return;
      this.downloadedPath = result.path;
      this.downloadedBytes = result.bytes;
      this.downloading = false;
      this.refreshDownloaded();
      await this.shareFile();
    } catch (error) {
      if (this.active) {
        this.downloadError = (error as Error).message;
        this.getUIContext().getPromptAction().showToast({ message: `下载失败：${this.downloadError}` });
      }
    } finally { if (this.active) { this.downloading = false; this.refreshDownloaded(); } }
  }

  private async shareFile(): Promise<void> {
    if (!this.selectedFile || !this.downloadedPath || !this.active) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mainWindow: window.Window = await window.getLastWindow(context);
      // Download completion can arrive after the user leaves this page or backgrounds the app.
      if (!this.active || !this.visible || !mainWindow.isWindowShowing()) return;
      await shareResource(context, this.downloadedPath, this.selectedFile.name, this.downloadedBytes);
    } catch (error) {
      if (this.active) this.getUIContext().getPromptAction().showToast({ message: `分享失败：${(error as Error).message}，点击已下载卡片重试` });
    }
  }

  build() {
    Column() {
      Refresh({ refreshing: $$this.refreshing }) {
        List() {
          if (this.loading || this.failure !== undefined || this.items.length === 0) {
            ListItem() {
              ResourceStateView({ loading: this.loading, failure: this.failure,
                emptyMessage: $r('app.string.resources_empty'),
                onRequestLogin: () => { this.onRequestLogin(); } })
            }.height('100%').id('resource-state-row')
          } else {
          ForEach(this.rows, (row: ResourceRow, index: number) => {
            ListItem() {
              Row({ space: $r('app.float.ui_space_content') }) {
                ResourceTypeIcon({ item: row.item })
                Column({ space: $r('app.float.ui_space_content') }) {
                  Text(row.item.name)
                    .fontSize($r('app.float.ui_text_card_title'))
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ui_text_primary'))
                  Text(row.item.folder ? $r('app.string.resource_folder') :
                    [row.item.type.toUpperCase().replace(/^\./, ''), formatSizeLabel(row.item.size)].filter((value: string) => value.length > 0).join(' · '))
                    .fontSize($r('app.float.ui_text_label'))
                    .fontColor($r('app.color.ui_text_secondary'))
                  if (row.item.creator.length > 0 || row.item.date.length > 0) {
                    Text([row.item.creator, row.item.date].filter((value: string) => value.length > 0).join(' · '))
                      .fontSize($r('app.float.ui_text_label'))
                      .fontColor($r('app.color.ui_text_tertiary'))
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (row.item.folder) {
                  Text('›').fontSize($r('app.float.ui_text_card_title')).fontColor($r('app.color.ui_text_tertiary'))
                } else {
                  ResourceDownloadStatus({ row: row })
                }
              }.width('100%').padding($r('app.float.ui_space_card'))
                .backgroundColor($r('app.color.ui_surface')).borderRadius($r('app.float.ui_radius_card'))
                .onClick(() => { this.open(row.item); })
                .enabled(!row.busy)
            }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
              .margin({ top: index === 0 ? $r('app.float.ui_space_page_top') : 0,
                bottom: index === this.items.length - 1 ? $r('app.float.ui_space_bottom_inset') : $r('app.float.ui_space_list') })
          }, (row: ResourceRow) => row.item.id)
          }
        }.width('100%').height('100%').edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }.width('100%').layoutWeight(1).onRefreshing(() => {
        hilog.info(0x0a01, 'PullRefresh', 'resources');
        this.refresh(true);
      })
    }.width('100%').height(LayoutPolicy.matchParent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.ui_canvas'))
      .onVisibleAreaChange([0, 1], (visible: boolean) => { this.visible = visible; })
  }
}
