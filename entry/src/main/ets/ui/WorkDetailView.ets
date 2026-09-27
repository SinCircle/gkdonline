import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { copySelectedWorkFile, discardSelectedWorkFile, uploadWorkAttachment, SelectedWorkFile } from '../api/WorkUploadApi';
import { WorkAttachmentView } from './WorkAttachmentView';
import { submitWork, loadWorkDraft, saveWorkDraft, previousSubmission, WorkSubmitResult } from '../api/WorkSubmitApi';
import { CourseWork } from '../data/WorkModels';
import { WorkDetail, WorkQuestion, QuestionKind, QuestionOption, QuestionAttachment, AnswerBinding, AnswerChoice, WorkAnswer } from '../data/WorkDetailModels';
import { fetchWorkDetail } from '../api/WorkDetailApi';
import { ApiError, ApiErrorKind } from '../api/errors';
import { SessionManager } from '../auth/SessionManager';
import { formatAttachmentSize } from '../common/FormatSize';
import { WorkAudioCapture, takeWorkPhoto, startWorkRecording, finishWorkRecording } from './WorkCapture';

@ComponentV2
export struct QuestionCard {
  @Require @Param question: WorkQuestion;
  @Param binding: AnswerBinding | undefined = undefined;
  @Param answer: string = '';
  @Param busy: boolean = false;
  @Param editable: boolean = false;
  @Event onAnswer: (value: string) => void = () => {};
  @Param attached: QuestionAttachment[] = [];
  @Param uploadEnabled: boolean = false;
  @Param pendingName: string = '';
  @Param uploadMessage: string = '';
  @Event onAddAttachment: () => void = () => {};
  @Event onTakePhoto: () => void = () => {};
  @Event onStartRecording: () => void = () => {};
  @Event onStopRecording: () => void = () => {};
  @Event onCancelRecording: () => void = () => {};
  @Param recording: boolean = false;
  @Event onUploadAttachment: () => void = () => {};
  @Event onDiscardAttachment: () => void = () => {};
  @Event onRemoveAttachment: (id: string) => void = () => {};
  @Local imageFailed: boolean = false;
  private choose(value: string): void {
    if (this.busy || !this.editable) return;
    if (this.binding?.mode === 'multiple') {
      this.onAnswer(this.answer.includes(value) ? this.answer.replace(value, '') : this.answer + value);
    } else this.onAnswer(value);
  }
  build() {
    Column({ space: $r('app.float.ui_space_loading') }) {
      Row() {
        Text(`${this.question.number}. ${this.question.kind}`)
          .fontSize($r('app.float.ui_text_card_title')).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ui_text_primary')).layoutWeight(1)
        if (this.question.points) {
          Text(`${this.question.points} 分`).fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
        }
      }.width('100%')
      if (this.question.kind === QuestionKind.UNSUPPORTED) {
        Text(`原始题号 ${this.question.number} · ${this.question.sourceType || '题型未识别'}，暂不支持此题型。`)
          .fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_text_secondary'))
      }
      if (this.question.stem.length > 0) {
        Text(this.question.stem).fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_text_primary'))
      }
      ForEach(this.question.images, (src: string) => {
        Image(src).width('100%').objectFit(ImageFit.Contain).onError(() => { this.imageFailed = true; })
      }, (src: string) => src)
      if (this.imageFailed) {
        Text('题干图片未能加载，当前题目内容不完整。').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_error'))
      }
      if ((!this.editable || !!this.binding?.reason) && (this.question.kind === QuestionKind.SINGLE || this.question.kind === QuestionKind.MULTIPLE)) {
        ForEach(this.question.options, (option: QuestionOption) => {
          Row({ space: $r('app.float.ui_space_content') }) {
            Text(option.label + '.').fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_accent'))
            Text(option.text).fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_text_primary')).layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top)
        }, (option: QuestionOption) => option.label)
      }
      if (this.question.attachments.length > 0) {
        Text('老师提供的附件')
          .fontSize($r('app.float.ui_text_label')).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ui_text_secondary'))
        ForEach(this.question.attachments, (file: QuestionAttachment) => {
          WorkAttachmentView({ file: file })
        }, (file: QuestionAttachment) => 'stem:' + file.objectId)
      }
      if (this.editable && this.binding && !this.binding.reason) {
        if (this.binding.mode === 'text') {
          TextArea({ text: this.answer, placeholder: '请输入答案' })
            .height($r('app.float.ui_size_answer_input')).fontSize($r('app.float.ui_text_body')).backgroundColor($r('app.color.ui_canvas'))
            .borderRadius($r('app.float.ui_radius_card')).enabled(!this.busy)
            .onChange((value: string) => { this.onAnswer(value); })
        } else if (this.binding.mode !== 'attachment') {
          ForEach(this.binding.choices, (choice: AnswerChoice) => {
            Row({ space: $r('app.float.ui_space_content') }) {
              if (this.binding?.mode === 'multiple') {
                Checkbox({ name: choice.value, group: this.question.id }).select(this.answer.includes(choice.value)).hitTestBehavior(HitTestMode.None)
              } else {
                Radio({ value: choice.value, group: this.question.id }).checked(this.answer === choice.value).hitTestBehavior(HitTestMode.None)
              }
              Text(choice.label + (choice.text ? '. ' + choice.text : '')).fontSize($r('app.float.ui_text_body')).layoutWeight(1)
            }.width('100%').padding($r('app.float.ui_space_content')).borderRadius($r('app.float.ui_radius_card'))
              .backgroundColor($r('app.color.ui_canvas')).enabled(!this.busy)
              .accessibilityText(choice.label + ' ' + choice.text + (this.answer.includes(choice.value) ? '，已选' : '，未选'))
              .onClick(() => { this.choose(choice.value); })
          }, (choice: AnswerChoice) => this.question.id + ':' + choice.label + ':' + choice.value)
        }
      } else if (this.binding?.reason) {
        Text(this.binding.reason).fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
      }
      if (!this.editable && this.question.previousAnswer) {
        Text(this.question.previousAnswer).fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_text_secondary'))
      }
      if (this.question.answerAttachments.length > 0 ||
        (this.editable && this.binding && !this.binding.reason &&
          (this.binding.mode === 'text' || this.binding.mode === 'attachment'))) {
        Text('我的附件')
          .fontSize($r('app.float.ui_text_label')).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ui_text_secondary'))
      }
      ForEach(this.question.answerAttachments, (file: QuestionAttachment) => {
        WorkAttachmentView({ file: file })
      }, (file: QuestionAttachment) => 'answer:' + file.objectId)
      if (this.editable && this.binding && !this.binding.reason &&
        (this.binding.mode === 'text' || this.binding.mode === 'attachment')) {
        ForEach(this.attached, (file: QuestionAttachment) => {
          Column({ space: $r('app.float.ui_space_content') }) {
            Text('已上传 · 尚未提交').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
            WorkAttachmentView({ file: file })
            Button('从本次作答移除').fontSize($r('app.float.ui_text_label')).backgroundColor($r('app.color.ui_canvas'))
              .fontColor($r('app.color.ui_text_secondary')).enabled(!this.busy)
              .onClick(() => { this.onRemoveAttachment(file.objectId); })
          }.width('100%').alignItems(HorizontalAlign.Start)
        }, (file: QuestionAttachment) => 'draft:' + this.question.id + ':' + file.objectId)
      }
      if (this.editable && this.binding && !this.binding.reason &&
        (this.binding.mode === 'text' || this.binding.mode === 'attachment')) {
        if (this.pendingName) {
          Text('待上传：' + this.pendingName).fontSize($r('app.float.ui_text_body'))
          Row({ space: $r('app.float.ui_space_content') }) {
            Button('上传我的附件').enabled(!this.busy).onClick(() => { this.onUploadAttachment(); })
            Button('取消选择').backgroundColor($r('app.color.ui_canvas')).fontColor($r('app.color.ui_text_secondary'))
              .enabled(!this.busy).onClick(() => { this.onDiscardAttachment(); })
          }
        } else if (this.recording) {
          Row({ space: $r('app.float.ui_space_content') }) {
            Text('录音中').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_accent')).layoutWeight(1)
            Button('完成录音').fontSize($r('app.float.ui_text_body'))
              .backgroundColor($r('app.color.ui_accent_soft')).fontColor($r('app.color.ui_accent'))
              .onClick(() => { this.onStopRecording(); })
            Button('取消').fontSize($r('app.float.ui_text_body'))
              .backgroundColor($r('app.color.ui_canvas')).fontColor($r('app.color.ui_text_secondary'))
              .onClick(() => { this.onCancelRecording(); })
          }.width('100%')
        } else {
          Row({ space: $r('app.float.ui_space_content') }) {
            Button('附件').layoutWeight(1).fontSize($r('app.float.ui_text_body'))
              .backgroundColor($r('app.color.ui_accent_soft')).fontColor($r('app.color.ui_accent'))
              .enabled(!this.busy && this.uploadEnabled).onClick(() => { this.onAddAttachment(); })
            Button('拍照').layoutWeight(1).fontSize($r('app.float.ui_text_body'))
              .backgroundColor($r('app.color.ui_accent_soft')).fontColor($r('app.color.ui_accent'))
              .enabled(!this.busy && this.uploadEnabled).onClick(() => { this.onTakePhoto(); })
            Button('录音').layoutWeight(1).fontSize($r('app.float.ui_text_body'))
              .backgroundColor($r('app.color.ui_accent_soft')).fontColor($r('app.color.ui_accent'))
              .enabled(!this.busy && this.uploadEnabled).onClick(() => { this.onStartRecording(); })
          }.width('100%')
        }
        if (this.uploadMessage) {
          Text(this.uploadMessage).fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
        }
        if (!this.uploadEnabled) {
          Text('当前页面未提供可识别的附件上传参数').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding($r('app.float.ui_space_card'))
      .backgroundColor($r('app.color.ui_surface')).borderRadius($r('app.float.ui_radius_card'))
  }
}

@ComponentV2
export struct WorkDetailView {
  @Require @Param work: CourseWork;
  @Event onRequestLogin: () => void = () => {};
  @Local private loading: boolean = true;
  @Local private detail: WorkDetail | undefined = undefined;
  @Local private failure: string = '';
  @Local private loginRequired: boolean = false;
  @Local private answers: WorkAnswer[] = [];
  @Local private submitting: boolean = false;
  @Local private confirming: boolean = false;
  @Local private feedback: string = '';
  @Local private locked: boolean = false;
  @Local private submitLogin: boolean = false;
  @Local private pendingUpload: SelectedWorkFile | undefined = undefined;
  @Local private uploadQuestion: string = '';
  @Local private uploading: boolean = false;
  @Local private picking: boolean = false;
  @Local private uploadMessage: string = '';
  @Local private recordingQuestion: string = '';
  private audioCapture: WorkAudioCapture | undefined = undefined;
  private filesDir: string = '';
  private active: boolean = false;
  private version: number = 0;
  private sessionKey: string = '';
  private listener: () => void = () => {};
  aboutToAppear(): void {
    this.active = true;
    this.listener = () => { this.sync(); };
    SessionManager.get().subscribe(this.listener); this.sync();
  }
  aboutToDisappear(): void {
    this.active = false; this.version++; SessionManager.get().unsubscribe(this.listener);
    if (this.audioCapture) {
      const capture: WorkAudioCapture = this.audioCapture;
      this.audioCapture = undefined;
      this.recordingQuestion = '';
      finishWorkRecording(capture, false).catch(() => {});
    }
  }
  private sync(): void {
    const state = SessionManager.get().snapshot();
    const key: string = `${state.loggedIn}:${state.savedAt}`;
    if (!state.ready || !this.active || key === this.sessionKey) return;
    this.sessionKey = key; this.refresh();
  }
  private async refresh(): Promise<void> {
    const version: number = ++this.version;
    this.loading = true; this.failure = ''; this.loginRequired = false;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('无法取得页面缓存目录');
      const detail: WorkDetail = await fetchWorkDetail(this.work.detailUrl, context.cacheDir);
      if (this.active && version === this.version) {
        this.detail = detail; this.filesDir = context.filesDir;
        this.locked = false; this.feedback = ''; this.submitLogin = false;
        if (detail.form) {
          this.answers = loadWorkDraft(this.filesDir, detail.form);
          const previous = previousSubmission(this.filesDir, detail.form);
          if (previous && ['success', 'pending', 'uncertain'].includes(previous.outcome)) {
            this.locked = true; this.feedback = previous.message;
          }
        } else this.answers = [];
      }
    } catch (error) {
      if (this.active && version === this.version) {
        this.loginRequired = error instanceof ApiError && error.kind === ApiErrorKind.SESSION_EXPIRED;
        this.failure = this.loginRequired ? '请先登录后查看作业题目' : `加载题目失败：${(error as Error).message}`;
      }
    } finally { if (this.active && version === this.version) this.loading = false; }
  }
  private updateAnswer(id: string, value: string): void {
    if (this.submitting || this.locked) return;
    this.answers = this.answers.map((a: WorkAnswer) => ({ questionId: a.questionId, value: a.questionId === id ? value : a.value, attachments: a.attachments } as WorkAnswer));
    if (this.detail?.form) {
      try { saveWorkDraft(this.filesDir, this.detail.form, this.answers); }
      catch (_) { this.feedback = '本机草稿保存失败，请暂时不要退出页面'; }
    }
  }
  private async pickAttachment(id: string): Promise<void> {
    if (this.submitting || this.confirming || this.locked || this.picking || this.uploading || this.pendingUpload || this.audioCapture) return;
    this.picking = true; this.uploadQuestion = id; this.uploadMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uris: string[] = await new picker.DocumentViewPicker(context).select({ maxSelectNumber: 1 });
      if (!this.active || uris.length === 0) return;
      this.pendingUpload = await copySelectedWorkFile(uris[0], context.cacheDir);
    } catch (error) { if (this.active) this.uploadMessage = '选择附件失败：' + (error as Error).message; }
    finally { this.picking = false; }
  }
  private async takePhoto(id: string): Promise<void> {
    if (this.submitting || this.confirming || this.locked || this.picking || this.uploading || this.pendingUpload || this.audioCapture) return;
    this.picking = true; this.uploadQuestion = id; this.uploadMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) throw new Error('无法取得应用缓存目录');
      const photo: SelectedWorkFile = await takeWorkPhoto(context);
      if (this.active) this.pendingUpload = photo;
      else discardSelectedWorkFile(photo);
    } catch (error) { if (this.active) this.uploadMessage = '拍照未完成：' + (error as Error).message; }
    finally { this.picking = false; }
  }
  private async beginRecording(id: string): Promise<void> {
    if (this.submitting || this.confirming || this.locked || this.picking || this.uploading || this.pendingUpload || this.audioCapture) return;
    this.picking = true; this.uploadQuestion = id; this.uploadMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) throw new Error('无法取得应用缓存目录');
      const capture: WorkAudioCapture = await startWorkRecording(context);
      if (this.active) { this.audioCapture = capture; this.recordingQuestion = id; }
      else await finishWorkRecording(capture, false);
    } catch (error) { if (this.active) this.uploadMessage = '录音未开始：' + (error as Error).message; }
    finally { this.picking = false; }
  }
  private async endRecording(keep: boolean): Promise<void> {
    if (!this.audioCapture || this.picking) return;
    this.picking = true;
    const capture: WorkAudioCapture = this.audioCapture;
    this.audioCapture = undefined; this.recordingQuestion = '';
    try {
      const file: SelectedWorkFile | undefined = await finishWorkRecording(capture, keep);
      if (file && this.active) this.pendingUpload = file;
      else if (file) discardSelectedWorkFile(file);
      if (!keep && this.active) this.uploadMessage = '已取消录音';
    } catch (error) { if (this.active) this.uploadMessage = '录音未保存：' + (error as Error).message; }
    finally { this.picking = false; }
  }
  private discardAttachment(): void {
    if (this.uploading) return;
    if (this.pendingUpload) discardSelectedWorkFile(this.pendingUpload);
    this.pendingUpload = undefined; this.uploadMessage = '';
  }
  private removeAttachment(id: string, objectId: string): void {
    if (this.submitting || this.confirming || this.uploading || !this.detail?.form) return;
    this.answers = this.answers.map((a: WorkAnswer) => ({ questionId: a.questionId, value: a.value,
      attachments: a.questionId === id ? a.attachments?.filter((f: QuestionAttachment) => f.objectId !== objectId) : a.attachments } as WorkAnswer));
    saveWorkDraft(this.filesDir, this.detail.form, this.answers);
    this.uploadQuestion = id; this.uploadMessage = '已从本次作答移除；没有删除服务器文件';
  }
  private async uploadAttachment(): Promise<void> {
    if (!this.pendingUpload || this.uploading || this.submitting || this.confirming || this.locked || this.audioCapture || !this.detail?.form) return;
    this.uploading = true; this.uploadMessage = '正在准备上传…';
    const file: SelectedWorkFile = this.pendingUpload;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('无法取得应用目录');
      const fresh: WorkDetail = await fetchWorkDetail(this.work.detailUrl, context.cacheDir);
      if (!this.active) return;
      if (!fresh.form || !fresh.upload || fresh.form.key !== this.detail.form.key || !fresh.form.bindings.some((b: AnswerBinding) => b.questionId === this.uploadQuestion && ['text', 'attachment'].includes(b.mode))) {
        throw new Error('作业状态或上传参数已变化，请重新加载详情');
      }
      const uploaded: QuestionAttachment = await uploadWorkAttachment(fresh.upload, file, this.filesDir, (sent: number, total: number) => {
        if (this.active) this.uploadMessage = total > 0 ? `正在上传 · 已发送 ${formatAttachmentSize(sent)} / ${formatAttachmentSize(total)}` : `正在上传 · 已发送 ${formatAttachmentSize(sent)}`;
      });
      this.answers = this.answers.map((a: WorkAnswer) => ({ questionId: a.questionId, value: a.value,
        attachments: a.questionId === this.uploadQuestion ? (a.attachments ?? []).filter((f: QuestionAttachment) => f.objectId !== uploaded.objectId).concat([uploaded]) : a.attachments } as WorkAnswer));
      // Local draft only. Uploading does not call a save-answer or work submission endpoint.
      saveWorkDraft(this.filesDir, this.detail.form, this.answers);
      this.pendingUpload = undefined; discardSelectedWorkFile(file);
      if (this.active) this.uploadMessage = `已上传 ${formatAttachmentSize(file.bytes)} 并加入本机作答；尚未提交作业`;
    } catch (error) { if (this.active) this.uploadMessage = '上传未完成：' + (error as Error).message + '。没有自动重试。'; }
    finally { this.uploading = false; }
  }
  private async confirmSubmit(): Promise<void> {
    if (this.confirming || this.submitting || this.locked || this.pendingUpload || this.uploading || this.picking || this.audioCapture || !this.detail?.form || this.detail.form.blockedReason) return;
    this.confirming = true;
    const empty: number = this.answers.filter((a: WorkAnswer) => !a.value.trim() && !(a.attachments?.length)).length;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '确认提交作业',
        message: this.detail.title + '\n提交后将交给老师，不能撤销。' + (empty ? `\n还有 ${empty} 题未作答，将一并提交。` : ''),
        buttons: [{ text: '继续作答', color: $r('app.color.ui_text_secondary') },
          { text: '确认提交', color: $r('app.color.ui_accent') }] });
      if (choice.index !== 1 || !this.active || !this.detail?.form) return;
      this.submitting = true; this.feedback = '正在提交，请勿重复操作'; this.submitLogin = false;
      const result: WorkSubmitResult = await submitWork(this.detail.form, this.answers, this.filesDir);
      if (!this.active) return;
      this.feedback = result.message;
      this.submitLogin = result.outcome === 'login';
      this.locked = ['success', 'pending', 'uncertain'].includes(result.outcome);
    } catch (error) { if (this.active) this.feedback = (error as Error).message; }
    finally { this.confirming = false; this.submitting = false; }
  }
  build() {
    Column() {
      if (this.loading || this.failure || !this.detail || this.detail.questions.length === 0) {
        Column({ space: $r('app.float.ui_space_section') }) {
          if (this.loading) {
            LoadingProgress().width($r('app.float.ui_size_loading')).height($r('app.float.ui_size_loading')).color($r('app.color.ui_accent'))
          }
          Text(this.loading ? '正在加载题目…' : this.failure || '这份作业暂无题目')
            .fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_text_secondary'))
          if (this.failure) {
            Button(this.loginRequired ? '登录' : '重新加载')
              .onClick(() => { if (this.loginRequired) this.onRequestLogin(); else this.refresh(); })
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding($r('app.float.ui_space_page'))
      } else {
        List() {
          ListItem() {
            Column({ space: $r('app.float.ui_space_content') }) {
              Text(this.detail.title).fontSize($r('app.float.ui_text_page_title')).fontWeight(FontWeight.Medium)
              Text(`共 ${this.detail.questions.length} 题 · ${this.detail.state}`).fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
              if (this.detail.description) { Text(this.detail.description).fontSize($r('app.float.ui_text_body')) }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page'), top: $r('app.float.ui_space_page_top') })
          ForEach(this.detail.questions, (q: WorkQuestion, index: number) => {
            ListItem() { QuestionCard({ question: q,
              binding: this.detail?.form?.bindings.find((b: AnswerBinding) => b.questionId === q.id),
              answer: this.answers.find((a: WorkAnswer) => a.questionId === q.id)?.value ?? '',
              editable: !!this.detail?.form && !this.locked, busy: this.submitting || this.confirming || this.uploading || this.picking,
              attached: this.answers.find((a: WorkAnswer) => a.questionId === q.id)?.attachments ?? [],
              uploadEnabled: !!this.detail?.upload && (!this.pendingUpload || this.uploadQuestion === q.id),
              recording: this.recordingQuestion === q.id,
              pendingName: this.uploadQuestion === q.id ? this.pendingUpload?.name ?? '' : '',
              uploadMessage: this.uploadQuestion === q.id ? this.uploadMessage : '',
              onAddAttachment: () => { this.pickAttachment(q.id); },
              onTakePhoto: () => { this.takePhoto(q.id); },
              onStartRecording: () => { this.beginRecording(q.id); },
              onStopRecording: () => { this.endRecording(true); },
              onCancelRecording: () => { this.endRecording(false); },
              onUploadAttachment: () => { this.uploadAttachment(); },
              onDiscardAttachment: () => { this.discardAttachment(); }, onRemoveAttachment: (id: string) => { this.removeAttachment(q.id, id); },
              onAnswer: (value: string) => { this.updateAnswer(q.id, value); } }) }
              .padding({ left: $r('app.float.ui_space_page'), right: $r('app.float.ui_space_page') })
              .margin({ top: $r('app.float.ui_space_list'), bottom: index === this.detail!.questions.length - 1 ? $r('app.float.ui_space_page') : 0 })
          }, (q: WorkQuestion) => q.id)
        }.width('100%').layoutWeight(1)
        if (this.detail.form) {
          Column({ space: $r('app.float.ui_space_content') }) {
            if (this.detail.form.blockedReason) {
              Text(this.detail.form.blockedReason).fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
            }
            if (this.feedback) {
              Text(this.feedback).fontSize($r('app.float.ui_text_body')).fontColor($r('app.color.ui_text_primary'))
            }
            if (this.submitLogin) {
              Button('重新登录').width('100%').onClick(() => { this.onRequestLogin(); })
            } else if (this.locked) {
              Button('刷新作业状态').width('100%').onClick(() => { this.refresh(); })
            } else {
              Button(this.submitting ? '正在提交…' : '提交作业').width('100%').height($r('app.float.ui_size_primary_button'))
                .backgroundColor($r('app.color.ui_accent')).fontColor(Color.White)
                .enabled(!this.submitting && !this.confirming && !this.uploading && !this.picking && !this.audioCapture && !this.pendingUpload && !this.detail.form.blockedReason)
                .onClick(() => { this.confirmSubmit(); })
              Text('草稿仅保存在本机；确认后才会提交').fontSize($r('app.float.ui_text_label')).fontColor($r('app.color.ui_text_secondary'))
            }
          }.width('100%').padding($r('app.float.ui_space_page')).backgroundColor($r('app.color.ui_surface'))
        }
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.ui_canvas'))
  }
}
