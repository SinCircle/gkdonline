import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { QuestionAttachment } from '../data/WorkDetailModels';
import { CourseResource } from '../data/ResourceModels';
import { workAttachmentResource } from '../api/WorkAttachmentParser';
import { prepareWorkAttachment } from '../api/WorkAttachmentApi';
import { downloadResource } from '../api/ResourceDownload';
import { cachedResource } from '../api/ResourceCache';
import { shareResource } from './ResourceShare';
import { ResourceTypeIcon } from './ResourceTypeIcon';

@ComponentV2
export struct WorkAttachmentView {
  @Require @Param file: QuestionAttachment;
  @Local private busy: boolean = false;
  @Local private downloaded: boolean = false;
  @Local private bytes: number = 0;
  @Local private total: number = 0;
  @Local private failed: boolean = false;
  private active: boolean = false;
  private visible: boolean = false;
  aboutToAppear(): void {
    this.active = true;
    const context = this.getUIContext().getHostContext();
    if (context) this.downloaded = cachedResource(workAttachmentResource(this.file), context.filesDir) !== undefined;
  }
  aboutToDisappear(): void { this.active = false; }
  private async download(): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.bytes = 0; this.total = 0; this.failed = false;
    let lastUpdate: number = 0;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) throw new Error('无法取得应用文件目录');
      const item: CourseResource = workAttachmentResource(this.file);
      await prepareWorkAttachment(item, context.filesDir);
      const result = await downloadResource(item, context.filesDir, (bytes: number, total?: number) => {
        if (this.active && Date.now() - lastUpdate >= 80) {
          lastUpdate = Date.now(); this.bytes = bytes; this.total = total && bytes <= total ? total : 0;
        }
      });
      if (!this.active) return;
      this.downloaded = true; this.bytes = result.bytes;
      try {
        const mainWindow = await window.getLastWindow(context);
        if (this.active && this.visible && mainWindow.isWindowShowing()) {
          await shareResource(context, result.path, item.name, result.bytes);
        }
      } catch (error) {
        if (this.active) this.getUIContext().getPromptAction().showToast({ message: `分享失败：${(error as Error).message}，点击已下载卡片重试` });
      }
    } catch (error) {
      if (this.active) {
        this.failed = true;
        this.getUIContext().getPromptAction().showToast({ message: `下载失败：${(error as Error).message}` });
      }
    } finally { if (this.active) this.busy = false; }
  }
  build() {
    Column() {
      Row({ space: $r('app.float.ui_space_content') }) {
        ResourceTypeIcon({ item: workAttachmentResource(this.file) })
        Text(this.file.name).fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_accent')).layoutWeight(1)
        Row() {
          if (this.busy) {
            Progress({ value: this.total > 0 ? this.bytes : 0, total: this.total > 0 ? this.total : 100,
              type: ProgressType.Ring })
              .width($r('app.float.ui_space_section')).height($r('app.float.ui_space_section'))
              .color($r('app.color.ui_accent'))
              .style({ strokeWidth: 2, status: this.total > 0 ? ProgressStatus.PROGRESSING : ProgressStatus.LOADING })
              .id('attachment-download-progress')
          } else if (this.failed) {
            Text('重试').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_error'))
              .id('attachment-download-retry')
          } else if (this.downloaded) {
            Text('已下载').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
              .id('attachment-downloaded')
          }
        }.width(56).height($r('app.float.ui_space_section'))
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      }.width('100%')
    }.width('100%').padding($r('app.float.ui_space_content')).backgroundColor($r('app.color.ui_canvas'))
      .borderRadius($r('app.float.ui_radius_card')).alignItems(HorizontalAlign.Start)
      .onVisibleAreaChange([0.0, 1.0], (visible: boolean) => { this.visible = visible; })
      .onClick(() => { this.download(); })
  }
}
