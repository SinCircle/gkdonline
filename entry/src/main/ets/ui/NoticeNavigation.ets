import { Notice } from '../data/Models';

// The home tab is owned by HomeView; Index listens here to push a destination.
export class NoticeNavigation {
  private static shared: NoticeNavigation = new NoticeNavigation();
  private listener: ((notice: Notice) => void) | undefined = undefined;

  static get(): NoticeNavigation { return NoticeNavigation.shared; }

  subscribe(listener: (notice: Notice) => void): void { this.listener = listener; }

  unsubscribe(listener: (notice: Notice) => void): void {
    if (this.listener === listener) this.listener = undefined;
  }

  open(notice: Notice): void { this.listener?.(notice); }
}
