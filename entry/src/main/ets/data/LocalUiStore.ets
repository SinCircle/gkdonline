import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Course } from './Models';

const DOMAIN: number = 0x0a01;
const TAG: string = 'LocalUiStore';
const PREF_NAME: string = 'ui_settings';

export interface CourseNote {
  id: string;
  text: string;
  done: boolean;
  createdAt: number;
}

export interface NotesResult {
  notes: CourseNote[];
  error: string;
}

export class CourseNotesNavigation {
  static open: (course: Course) => void = () => {};
}

export class LocalUiStore {
  private static instance: LocalUiStore = new LocalUiStore();
  private pref?: preferences.Preferences;
  private notesListeners: Set<(courseId: string, notes: CourseNote[]) => void> =
    new Set<(courseId: string, notes: CourseNote[]) => void>();

  static get(): LocalUiStore { return LocalUiStore.instance; }

  init(context: Context | undefined): void {
    if (this.pref !== undefined) return;
    if (context === undefined) throw new Error('无法读取本机设置，请稍后重试');
    try {
      this.pref = preferences.getPreferencesSync(context, { name: PREF_NAME });
    } catch (error) {
      hilog.error(DOMAIN, TAG, '打开本机设置失败: %{public}s', (error as Error).message);
      throw new Error('无法读取本机设置，请稍后重试');
    }
  }

  private storage(): preferences.Preferences {
    if (this.pref === undefined) throw new Error('本机设置尚未就绪，请稍后重试');
    return this.pref;
  }

  private noteKey(courseId: string): string { return `course_notes_v1_${courseId}`; }

  readNotes(courseId: string): NotesResult {
    let raw: string;
    try {
      raw = this.storage().getSync(this.noteKey(courseId), '[]') as string;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '读取课程备注失败 %{public}s: %{public}s', courseId, (error as Error).message);
      return { notes: [], error: '备注读取失败，请稍后重试' };
    }
    try {
      const notes: CourseNote[] = JSON.parse(raw) as CourseNote[];
      if (!Array.isArray(notes) || !notes.every((note: CourseNote) =>
        typeof note.id === 'string' && typeof note.text === 'string' &&
        typeof note.done === 'boolean' && typeof note.createdAt === 'number')) {
        throw new Error('备注格式不正确');
      }
      return { notes: notes, error: '' };
    } catch (error) {
      // 不写回损坏的键，保留原始字节以便恢复。
      hilog.error(DOMAIN, TAG, '课程备注 JSON 损坏，保留原值 %{public}s: %{public}s', courseId,
        (error as Error).message);
      return { notes: [], error: '这门课的备注数据无法读取，原始数据已保留' };
    }
  }

  saveNotes(courseId: string, notes: CourseNote[]): void {
    const old: NotesResult = this.readNotes(courseId);
    if (old.error) throw new Error(old.error);
    const pref: preferences.Preferences = this.storage();
    const key: string = this.noteKey(courseId);
    const previous: string = pref.getSync(key, '[]') as string;
    try {
      pref.putSync(key, JSON.stringify(notes));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '保存课程备注失败 %{public}s: %{public}s', courseId, (error as Error).message);
      try { pref.putSync(key, previous); pref.flushSync(); } catch (rollbackError) {
        hilog.error(DOMAIN, TAG, '恢复课程备注失败 %{public}s: %{public}s', courseId,
          (rollbackError as Error).message);
      }
      throw new Error('备注保存失败，请重试');
    }
    this.notesListeners.forEach((listener: (id: string, value: CourseNote[]) => void) => listener(courseId, notes));
  }

  subscribeNotes(listener: (courseId: string, notes: CourseNote[]) => void): void {
    this.notesListeners.add(listener);
  }

  unsubscribeNotes(listener: (courseId: string, notes: CourseNote[]) => void): void {
    this.notesListeners.delete(listener);
  }

  private readMap(key: string): Record<string, boolean> {
    try {
      const raw: string = this.storage().getSync(key, '{}') as string;
      const value: Record<string, boolean> = JSON.parse(raw) as Record<string, boolean>;
      if (value === null || Array.isArray(value) || typeof value !== 'object' ||
        !Object.keys(value).every((id: string) => typeof value[id] === 'boolean')) {
        throw new Error('覆盖层格式不正确');
      }
      return value;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '读取本机覆盖层失败 %{public}s: %{public}s', key, (error as Error).message);
      throw new Error('本机操作记录无法读取，原始数据已保留');
    }
  }

  private saveMap(key: string, value: Record<string, boolean>): void {
    const pref: preferences.Preferences = this.storage();
    const previous: string = pref.getSync(key, '{}') as string;
    try {
      pref.putSync(key, JSON.stringify(value));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '保存本机覆盖层失败 %{public}s: %{public}s', key, (error as Error).message);
      try { pref.putSync(key, previous); pref.flushSync(); } catch (rollbackError) {
        hilog.error(DOMAIN, TAG, '恢复本机覆盖层失败 %{public}s: %{public}s', key,
          (rollbackError as Error).message);
      }
      throw new Error('本机操作保存失败，请重试');
    }
  }

  readCoursePins(): Record<string, boolean> { return this.readMap('course_pins_v1'); }
  saveCoursePins(value: Record<string, boolean>): void { this.saveMap('course_pins_v1', value); }
  readNoticePins(): Record<string, boolean> { return this.readMap('notice_pins_v1'); }
  saveNoticePins(value: Record<string, boolean>): void { this.saveMap('notice_pins_v1', value); }
  readNoticeRead(): Record<string, boolean> { return this.readMap('notice_read_v1'); }
  saveNoticeRead(value: Record<string, boolean>): void { this.saveMap('notice_read_v1', value); }
}
