/**
 * 会话状态的唯一来源。
 *
 * 普通服务单例；界面通过订阅通知把快照复制到自己的 @Local 字段。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { CookieEntry, hasAuthCookie, selectCookie } from './CookieUtil';
import { SessionSnapshot, SessionStore } from './SessionStore';

const DOMAIN: number = 0x0a01;
const TAG: string = 'SessionManager';

export enum ServerCheckStatus {
  UNCHECKED = 0,
  PASSED = 1,
  FAILED = 2,
}

export interface SessionState {
  ready: boolean;
  loggedIn: boolean;
  loginOrigin: string;
  savedAt: number;
  serverCheck: ServerCheckStatus;
}

export class SessionManager {
  private static shared: SessionManager = new SessionManager();

  /** 本地凭证是否已经读过一遍。读完之前界面只显示加载态。 */
  ready: boolean = false;
  loggedIn: boolean = false;
  /** 登录成功后落到的域。M1 靠它推断 base URL（HANDOFF 11 节 #2）。 */
  loginOrigin: string = '';
  savedAt: number = 0;
  serverCheck: ServerCheckStatus = ServerCheckStatus.UNCHECKED;

  private entries: CookieEntry[] = [];
  private listeners: Array<() => void> = [];

  static get(): SessionManager {
    return SessionManager.shared;
  }

  subscribe(listener: () => void): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unsubscribe(listener: () => void): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  snapshot(): SessionState {
    return {
      ready: this.ready,
      loggedIn: this.loggedIn,
      loginOrigin: this.loginOrigin,
      savedAt: this.savedAt,
      serverCheck: this.serverCheck,
    };
  }

  private notifyListeners(): void {
    for (const listener of this.listeners.slice()) {
      try {
        listener();
      } catch (error) {
        hilog.error(DOMAIN, TAG, '会话状态订阅者执行失败');
      }
    }
  }

  setServerCheck(status: ServerCheckStatus): void {
    this.serverCheck = status;
    this.notifyListeners();
  }

  /** App 启动时调用一次：把上次登录的凭证读回内存。 */
  async init(): Promise<void> {
    this.serverCheck = ServerCheckStatus.UNCHECKED;
    try {
      const snapshot: SessionSnapshot | undefined = await SessionStore.load();
      if (snapshot !== undefined) {
        this.entries = snapshot.cookies;
        this.loginOrigin = snapshot.loginOrigin;
        this.savedAt = snapshot.savedAt;
        this.loggedIn = hasAuthCookie(snapshot.cookies);
      }
    } catch (error) {
      // 读失败不能挡住启动，但也不能悄悄咽掉 —— 记日志，界面按未登录走。
      hilog.error(DOMAIN, TAG, '读取本地凭证失败');
    }
    this.ready = true;
    this.notifyListeners();
  }

  /** 登录成功后把 WebView 里取到的 Cookie 收下并落盘。 */
  async adopt(entries: CookieEntry[], loginOrigin: string): Promise<void> {
    const savedAt: number = Date.now();
    await SessionStore.save({ cookies: entries, loginOrigin: loginOrigin, savedAt: savedAt });
    this.entries = entries;
    this.loginOrigin = loginOrigin;
    this.savedAt = savedAt;
    this.loggedIn = hasAuthCookie(entries);
    this.serverCheck = ServerCheckStatus.UNCHECKED;
    hilog.info(DOMAIN, TAG, '已保存 %{public}d 条域的凭证，登录域 %{public}s',
      entries.length, loginOrigin);
    this.notifyListeners();
  }

  /** 退出登录：本地凭证删除成功后，再清内存和本应用的 Web Cookie。 */
  async logout(): Promise<void> {
    await SessionStore.clear();
    try {
      await webview.WebCookieManager.clearAllCookies();
      await webview.WebCookieManager.saveCookieAsync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '本地凭证已删除，但 Web Cookie 清除失败');
    }
    this.entries = [];
    this.loginOrigin = '';
    this.savedAt = 0;
    this.loggedIn = false;
    this.serverCheck = ServerCheckStatus.UNCHECKED;
    hilog.info(DOMAIN, TAG, '已退出登录');
    this.notifyListeners();
  }

  /** 发往 host 的 Cookie 头。没有对应域的凭证时返回空串。 */
  cookieHeaderFor(host: string): string {
    return selectCookie(this.entries, host);
  }

  /** 存了哪些域，仅用于界面展示和排查。 */
  domains(): string[] {
    const result: string[] = [];
    for (const entry of this.entries) {
      result.push(entry.domain);
    }
    return result;
  }
}
