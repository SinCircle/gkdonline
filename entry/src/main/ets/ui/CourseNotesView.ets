import { Course } from '../data/Models';
import { CourseNote, LocalUiStore, NotesResult } from '../data/LocalUiStore';

@ComponentV2
export struct CourseNotesView {
  @Require @Param course: Course;
  @Local private notes: CourseNote[] = [];
  @Local private draft: string = '';
  @Local private errorText: string = '';
  private store: LocalUiStore = LocalUiStore.get();

  aboutToAppear(): void {
    try {
      this.store.init(this.getUIContext().getHostContext());
      const result: NotesResult = this.store.readNotes(this.course.id);
      this.notes = result.notes;
      this.errorText = result.error;
    } catch (error) {
      this.notes = [];
      this.errorText = (error as Error).message;
    }
  }

  private commit(next: CourseNote[]): void {
    try {
      this.store.saveNotes(this.course.id, next);
      this.notes = next;
      this.errorText = '';
    } catch (error) {
      this.errorText = (error as Error).message;
    }
  }

  private addNote(): void {
    const text: string = this.draft.trim();
    if (!text) return;
    const next: CourseNote[] = this.notes.concat([{ id: `${Date.now()}-${Math.random()}`,
      text: text, done: false, createdAt: Date.now() }]);
    try {
      this.store.saveNotes(this.course.id, next);
      this.notes = next;
      this.draft = '';
      this.errorText = '';
    } catch (error) {
      this.errorText = (error as Error).message;
    }
  }

  private updateNote(id: string, text: string, done: boolean): void {
    const next: CourseNote[] = this.notes.map((note: CourseNote) => note.id === id ?
      { id: note.id, text: text, done: done, createdAt: note.createdAt } : note);
    this.commit(next);
  }

  build() {
    Column({ space: $r('app.float.ui_space_list') }) {
      Text(this.course.name)
        .fontSize($r('app.float.ui_text_card_title'))
        .fontColor($r('app.color.ui_text_primary'))
        .width('100%')
        .draggable(false)
      if (this.errorText) {
        Text(this.errorText)
          .fontSize($r('app.float.ui_text_body'))
          .fontColor($r('app.color.ui_error'))
          .width('100%')
      }
      Row({ space: $r('app.float.ui_space_content') }) {
        TextInput({ text: this.draft, placeholder: '新增备注' })
          .layoutWeight(1)
          .onChange((value: string) => { this.draft = value; })
        Button('新增')
          .enabled(!this.errorText && !!this.draft.trim())
          .onClick(() => { this.addNote(); })
      }.width('100%')
      List() {
        ForEach(this.notes, (note: CourseNote) => {
          ListItem() {
            Row({ space: $r('app.float.ui_space_content') }) {
              Checkbox({ name: note.id })
                .select(note.done)
                .width(16).height(16)
                .onChange((checked: boolean) => { this.updateNote(note.id, note.text, checked); })
              TextInput({ text: note.text })
                .layoutWeight(1)
                .fontColor(note.done ? $r('app.color.ui_text_secondary') : $r('app.color.ui_text_primary'))
                .onChange((value: string) => { this.updateNote(note.id, value, note.done); })
              Button('删除')
                .fontColor($r('app.color.ui_error'))
                .backgroundColor($r('app.color.ui_surface'))
                .onClick(() => { this.commit(this.notes.filter((item: CourseNote) => item.id !== note.id)); })
            }.width('100%').padding($r('app.float.ui_space_content'))
          }
        }, (note: CourseNote) => note.id)
      }.width('100%').layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding($r('app.float.ui_space_page'))
    .backgroundColor($r('app.color.ui_canvas'))
  }
}
