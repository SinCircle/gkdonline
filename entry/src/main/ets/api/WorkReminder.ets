import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import wantAgent from '@ohos.wantAgent';
import { Course } from '../data/Models';
import { CourseWork } from '../data/WorkModels';
import { SessionManager } from '../auth/SessionManager';

const AHEAD_MINUTES: number = 48 * 60;
const inFlight: Set<string> = new Set<string>();

export interface DueWork { key: string; id: string; title: string; detailUrl: string; remainingMinutes: number; }
export interface ReminderResult { sent: number; already: number; active: number; }

// The real course list exposes a relative deadline such as "剩余41小时32分钟".
// Unknown, expired, submitted or unparseable entries are never notified.
export function remainingMinutes(text: string): number | undefined {
  const match: RegExpExecArray | null = /^剩余\s*(?:(\d+)天)?(?:(\d+)小时)?(?:(\d+)分钟)?$/.exec(text.trim());
  if (!match || (!match[1] && !match[2] && !match[3])) return undefined;
  const minutes: number = Number(match[1] ?? 0) * 1440 + Number(match[2] ?? 0) * 60 + Number(match[3] ?? 0);
  return minutes > 0 ? minutes : undefined;
}

export function dueWorks(course: Course, works: CourseWork[], uid: string): DueWork[] {
  if (!/^\d+$/.test(uid)) return [];
  const due: DueWork[] = [];
  for (const work of works) {
    if (work.status.trim() !== '未交' || !/^\d+$/.test(work.id)) continue;
    const minutes: number | undefined = remainingMinutes(work.deadlineText);
    if (minutes !== undefined && minutes <= AHEAD_MINUTES) {
      due.push({ key: `${uid}:${course.courseId}:${course.classId}:${work.id}`, id: work.id,
        title: work.title, detailUrl: work.detailUrl, remainingMinutes: minutes });
    }
  }
  return due;
}

function readKeys(path: string): string[] {
  if (!fs.accessSync(path)) return [];
  const keys: string[] = JSON.parse(fs.readTextSync(path)) as string[];
  if (!Array.isArray(keys) || keys.some((key: string) => typeof key !== 'string')) throw new Error('本地提醒记录损坏，已停止发送以避免重复提醒');
  return keys;
}

function saveKeys(path: string, keys: string[]): void {
  const temporary: string = path + '.part';
  const file: fs.File = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { fs.writeSync(file.fd, JSON.stringify(keys)); } finally { fs.closeSync(file); }
  fs.renameSync(temporary, path);
}

function notificationId(key: string): number {
  let value: number = 0;
  for (let index: number = 0; index < key.length; index++) value = (value * 31 + key.charCodeAt(index)) | 0;
  return (value & 0x7fffffff) || 1;
}

// Called when an actual course work list is loaded, without polling or a fake
// scheduled percentage. Persist the reservation before publishing so a restart
// cannot send the same work twice.
export async function remindDueWorks(course: Course, works: CourseWork[], context: common.UIAbilityContext): Promise<ReminderResult> {
  const settings: preferences.Preferences = preferences.getPreferencesSync(context, { name: 'ui_settings' });
  if (!(settings.getSync('reminders_enabled', true) as boolean)) {
    hilog.info(0x0a01, 'WorkReminder', '作业截止提醒已关闭，跳过发布');
    return { sent: 0, already: 0, active: 0 };
  }
  const cookie: string = SessionManager.get().cookieHeaderFor('mooc.mooc.ucas.edu.cn');
  const uid: string = /(?:^|;\s*)_uid=(\d+)/.exec(cookie)?.[1] ?? '';
  const due: DueWork[] = dueWorks(course, works, uid);
  const outcome: ReminderResult = { sent: 0, already: 0, active: 0 };
  if (due.length === 0) return outcome;
  const path: string = context.filesDir + '/work-reminders-v1.json';
  let keys: string[] = readKeys(path);
  if (due.every((work: DueWork) => keys.includes(work.key))) return { sent: 0, already: due.length, active: 0 };
  if (!await notificationManager.isNotificationEnabled()) {
    await notificationManager.requestEnableNotification(context);
    if (!await notificationManager.isNotificationEnabled()) throw new Error('系统通知尚未开启，无法发送作业提醒');
  }
  for (const work of due) {
    if (keys.includes(work.key) || inFlight.has(work.key)) { outcome.already++; continue; }
    inFlight.add(work.key);
    try {
      keys = readKeys(path);
      if (keys.includes(work.key)) { outcome.already++; continue; }
      // Reserve first. On an uncertain publish failure, keep the reservation to
      // honor the once-per-work rule; the UI reports the failure.
      saveKeys(path, keys.concat([work.key]));
      const id: number = notificationId(work.key);
      const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: 'cn.edu.ucas.gkdonline',
        abilityName: 'EntryAbility', parameters: { gkdWorkId: work.id, gkdWorkTitle: work.title,
          gkdWorkUrl: work.detailUrl, gkdCourseId: course.courseId, gkdClassId: course.classId } }],
        operationType: wantAgent.OperationType.START_ABILITY, requestCode: id,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
      await notificationManager.publish({ id: id, appMessageId: work.key,
        wantAgent: agent,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: '作业即将截止', text: `${course.name} · ${work.title}，${work.remainingMinutes >= 60 ?
            `剩余约 ${Math.ceil(work.remainingMinutes / 60)} 小时` : `剩余 ${work.remainingMinutes} 分钟`}` } } });
      outcome.sent++;
      try {
        const active = await notificationManager.getActiveNotifications();
        if (active.some((request: notificationManager.NotificationRequest) => request.id === id)) outcome.active++;
      } catch (_) { /* Published, but active-list inspection may be unavailable. */ }
    } finally { inFlight.delete(work.key); }
  }
  return outcome;
}
