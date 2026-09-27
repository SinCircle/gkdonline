import { Course } from './Models';
import { CourseWork } from './WorkModels';

export interface WorkDetailRoute {
  work: CourseWork;
  course?: Course;
  courseId?: string;
  classId?: string;
}

export interface WorkChanged {
  workId: string;
  courseId: string;
  classId: string;
}

export interface PendingWorkLink {
  workId: string;
  title: string;
  detailUrl: string;
  courseId: string;
  classId: string;
}

export class WorkNavigation {
  private static shared: WorkNavigation = new WorkNavigation();
  private changedListeners: Array<(change: WorkChanged) => void> = [];
  private linkListeners: Array<() => void> = [];
  private pending: PendingWorkLink | undefined = undefined;

  static get(): WorkNavigation { return WorkNavigation.shared; }

  subscribeChanged(listener: (change: WorkChanged) => void): void {
    if (!this.changedListeners.includes(listener)) this.changedListeners.push(listener);
  }

  unsubscribeChanged(listener: (change: WorkChanged) => void): void {
    const index: number = this.changedListeners.indexOf(listener);
    if (index >= 0) this.changedListeners.splice(index, 1);
  }

  publishChanged(change: WorkChanged): void {
    for (const listener of this.changedListeners.slice()) {
      try { listener(change); } catch (_) { /* One view must not prevent the other from refreshing. */ }
    }
  }

  subscribeLink(listener: () => void): void {
    if (!this.linkListeners.includes(listener)) this.linkListeners.push(listener);
  }

  unsubscribeLink(listener: () => void): void {
    const index: number = this.linkListeners.indexOf(listener);
    if (index >= 0) this.linkListeners.splice(index, 1);
  }

  offerLink(link: PendingWorkLink): void {
    this.pending = link;
    for (const listener of this.linkListeners.slice()) {
      try { listener(); } catch (_) { /* Keep the pending link for the next appearance. */ }
    }
  }

  peekLink(): PendingWorkLink | undefined { return this.pending; }

  clearLink(): void {
    this.pending = undefined;
  }
}
