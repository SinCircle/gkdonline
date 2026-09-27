import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CookieEntry, hasAuthCookie } from '../auth/CookieUtil';
import { SessionManager } from '../auth/SessionManager';
import { isLoginRedirect } from '../api/RedirectRules';
import { hostOf, originOf } from '../common/UrlUtil';

const DOMAIN: number = 0x0a01;
const TAG: string = 'LoginView';
const LOGIN_URL: string = 'https://sep.ucas.edu.cn/?loginFrom=/portal/site/441/2142';
const SPACE_URL: string = 'https://i.mooc.ucas.edu.cn/space/';
const MOOC_URL: string = 'https://mooc.ucas.edu.cn/';
const MOOC_MOOC_URL: string = 'https://mooc.mooc.ucas.edu.cn/';
const UCAS_PASSPORT_URL: string = 'https://passport.mooc.ucas.edu.cn/';
const SEP_URL: string = 'https://sep.ucas.ac.cn/';
const CHAOXING_PASSPORT_URL: string = 'https://passport2.chaoxing.com/';
const CHAOXING_ROOT_URL: string = 'https://chaoxing.com/';

@ComponentV2
export struct LoginView {
  @Event onLoggedIn: () => void = () => {};
  @Event onBack: () => void = () => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  @Local private checking: boolean = false;
  @Local private showNoSession: boolean = false;
  @Local private showLoadError: boolean = false;
  @Local private showCaptureError: boolean = false;
  @Local private showPageNotReady: boolean = false;
  private pendingUrl: string = '';

  private retryCapture(): void {
    this.showPageNotReady = false;
    try {
      const url: string = this.controller.getUrl();
      if (url.length === 0) {
        this.showPageNotReady = true;
        return;
      }
      this.capture(url);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      if (err.code === 17100001) {
        hilog.warn(DOMAIN, TAG, 'Web 尚未附着，稍后再检查登录状态');
      } else {
        hilog.error(DOMAIN, TAG, '读取当前网页地址失败，错误码 %{public}d', err.code);
      }
      this.showPageNotReady = true;
    }
  }

  private async fetchFor(url: string): Promise<CookieEntry | undefined> {
    const domain: string = hostOf(url);
    if (domain.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Cookie 探测 URL 的主机解析失败');
      return undefined;
    }
    try {
      const cookie: string = await webview.WebCookieManager.fetchCookie(url);
      if (cookie.length > 0) {
        return { domain: domain, cookie: cookie, sourceUrl: url };
      }
      hilog.warn(DOMAIN, TAG, '域 %{public}s 下暂无 Cookie', domain);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      if (err.code === 17100002) {
        hilog.warn(DOMAIN, TAG, '域 %{public}s 下暂无 Cookie', domain);
      } else {
        hilog.error(DOMAIN, TAG, '读取域 %{public}s 的 Cookie 失败，错误码 %{public}d', domain, err.code);
      }
    }
    return undefined;
  }

  private async capture(url: string): Promise<void> {
    if (this.checking) {
      this.pendingUrl = url;
      return;
    }
    this.checking = true;
    try {
      await this.captureOnce(url);
      const pending: string = this.pendingUrl;
      this.pendingUrl = '';
      if (pending.length > 0) {
        await this.captureOnce(pending);
      }
    } finally {
      if (this.pendingUrl.length > 0) {
        hilog.warn(DOMAIN, TAG, '连续页面跳转超过一次补抓，最后主机 %{public}s', hostOf(this.pendingUrl));
      }
      this.pendingUrl = '';
      this.checking = false;
    }
  }

  private async captureOnce(url: string): Promise<void> {
    this.showNoSession = false;
    this.showCaptureError = false;
    try {
      const host: string = hostOf(url);
      const origin: string = originOf(url);
      if (host.length === 0 || origin.length === 0 || isLoginRedirect(url)) {
        this.showNoSession = true;
        return;
      }
      await webview.WebCookieManager.saveCookieAsync();
      const entries: CookieEntry[] = [];
      // 根域探测只收集浏览器会发往根域的 Cookie，不能把 passport 的 host-only Cookie 放宽为全域。
      const candidates: string[] = [SPACE_URL, MOOC_URL, MOOC_MOOC_URL, UCAS_PASSPORT_URL, SEP_URL,
        CHAOXING_PASSPORT_URL, url, CHAOXING_ROOT_URL];
      for (const candidate of candidates) {
        const found: CookieEntry | undefined = await this.fetchFor(candidate);
        if (found === undefined) continue;
        const prior: number = entries.findIndex((entry: CookieEntry) => entry.domain === found.domain);
        if (prior >= 0) {
          entries[prior] = found;
        } else {
          entries.push(found);
        }
      }
      if (!hasAuthCookie(entries)) {
        this.showNoSession = true;
        return;
      }
      await SessionManager.get().adopt(entries, origin);
      this.onLoggedIn();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '保存登录状态失败，请检查 Asset Store 与各域凭证字节数');
      this.showCaptureError = true;
    }
  }

  build() {
    Column() {
      Text($r('app.string.login_instruction'))
        .fontSize($r('app.float.ui_text_body'))
        .fontColor($r('app.color.ui_text_secondary'))
        .width('100%')
      Web({ src: LOGIN_URL, controller: this.controller })
        .backgroundColor($r('app.color.ui_surface'))
        .metaViewport(true)
        // SEP 表单右缘实测 365 CSS px，大于本页 342 px 视口；保留缩放，移除横向锁定。
        .initialScale(80)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onPageBegin(() => {
          this.showLoadError = false;
        })
        .onPageEnd((event: OnPageEndEvent) => {
          this.showPageNotReady = false;
          if (!isLoginRedirect(event.url)) {
            this.capture(event.url);
          }
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (event.request.isMainFrame()) {
            this.showLoadError = true;
            hilog.error(DOMAIN, TAG, '登录网页加载失败，主机 %{public}s',
              hostOf(event.request.getRequestUrl()));
          }
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          if (event.request.isMainFrame()) {
            this.showLoadError = true;
            hilog.error(DOMAIN, TAG, '登录网页 HTTP %{public}d，主机 %{public}s',
              event.response.getResponseCode(), hostOf(event.request.getRequestUrl()));
          }
        })
        .width('100%')
        .layoutWeight(1)
      if (this.showLoadError) {
        Text($r('app.string.login_load_error'))
          .fontSize($r('app.float.ui_text_label'))
          .fontColor($r('app.color.ui_error'))
      }
      if (this.showNoSession) {
        Text($r('app.string.login_not_detected'))
          .fontSize($r('app.float.ui_text_label'))
          .fontColor($r('app.color.ui_text_secondary'))
      }
      if (this.showCaptureError) {
        Text($r('app.string.login_capture_error'))
          .fontSize($r('app.float.ui_text_label'))
          .fontColor($r('app.color.ui_error'))
      }
      if (this.showPageNotReady) {
        Text($r('app.string.login_page_not_ready'))
          .fontSize($r('app.float.ui_text_label'))
          .fontColor($r('app.color.ui_text_secondary'))
      }
      Button($r('app.string.login_confirm'))
        .width('100%')
        .height($r('app.float.ui_size_primary_button'))
        .fontSize($r('app.float.ui_text_button'))
        .borderRadius($r('app.float.ui_radius_button'))
        .backgroundColor($r('app.color.ui_accent'))
        .margin({ top: $r('app.float.ui_space_page') })
        .enabled(!this.checking)
        .onClick(() => { this.retryCapture(); })
    }
    .width('100%').height('100%')
    .padding({ left: $r('app.float.ui_space_page'),
      right: $r('app.float.ui_space_page'),
      top: $r('app.float.ui_space_page_top'),
      bottom: $r('app.float.ui_space_page') })
    .backgroundColor($r('app.color.ui_surface'))
  }
}
