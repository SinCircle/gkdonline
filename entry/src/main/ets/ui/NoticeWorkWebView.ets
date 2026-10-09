import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SessionManager } from '../auth/SessionManager';
import { parseCookies } from '../auth/CookieUtil';
import { isLoginRedirect } from '../api/RedirectRules';
import { hostOf, originOf } from '../common/UrlUtil';

const DOMAIN: number = 0x0a01;
const TAG: string = 'NoticeWorkWeb';
/** 只点了那一条作业但页面迟迟不换时给的提示。 */
const HINT: string = '已打开该课程的作业列表，请点对应作业';
const JUMP_TIMEOUT_MS: number = 8000;

/** 应用内浏览器要打开的作业入口：列表页地址 + 要精确跳到的那一条作业 id（可为空）。 */
export interface NoticeWorkRoute {
  url: string;
  workId: string;
}

@ComponentV2
export struct NoticeWorkWebView {
  @Param url: string = '';
  @Param workId: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 装会话 / 地址本身的问题，加载前就知道，且与后面某次导航无关。 */
  @Local private notice: string = '';
  /** Web 自己报的加载失败或 HTTP 错误。 */
  @Local private failure: string = '';
  /** 当前停在服务端登录页。 */
  @Local private loginExpired: boolean = false;
  /** 没跳到那一条作业时的人话提示。 */
  @Local private hint: string = '';
  private active: boolean = false;
  /** 已经跳到目标作业了。 */
  private jumped: boolean = false;
  /** 精确点击只做一次。 */
  private attempts: number = 0;

  aboutToAppear(): void {
    this.active = true;
    const origin: string = originOf(this.url);
    if (origin.length === 0 || !/^https:\/\//i.test(origin)) {
      this.notice = '这条通知的作业地址不是 https，浏览器里可能要求重新登录';
      hilog.warn(DOMAIN, TAG, '作业入口不是可装会话的 https 地址，主机 %{public}s', hostOf(this.url));
      return;
    }
    const host: string = hostOf(this.url);
    const cookie: string = host.length > 0 ? SessionManager.get().cookieHeaderFor(host) : '';
    const pairs: Map<string, string> = parseCookies(cookie);
    if (pairs.size === 0) {
      this.notice = '本机没有这个域的登录会话，页面可能要求重新登录';
      hilog.warn(DOMAIN, TAG, '本机没有 %{public}s 的会话，浏览器可能落到登录页', host);
      return;
    }
    // 一条一条装：整串 "a=1; b=2" 塞进去时 ArkWeb 按 Set-Cookie 解析，
    // 第二项之后会被当成属性丢掉，结果只装进第一条（实测落到登录页）。
    let installed: number = 0;
    let rejected: number = 0;
    pairs.forEach((value: string, name: string) => {
      if (name.length === 0 || value.length === 0) return;
      try {
        webview.WebCookieManager.configCookieSync(origin, name + '=' + value);
        installed++;
      } catch (error) {
        rejected++;
        hilog.error(DOMAIN, TAG, '会话 Cookie %{public}s 装入失败，错误码 %{public}d', name, (error as BusinessError).code);
      }
    });
    let readBack: number = -1;
    try {
      readBack = parseCookies(webview.WebCookieManager.fetchCookieSync(origin)).size;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '回读 %{public}s 的会话失败，错误码 %{public}d', origin, (error as BusinessError).code);
    }
    hilog.info(DOMAIN, TAG, '会话装入 %{public}s：待装 %{public}d 条，成功 %{public}d 条，失败 %{public}d 条，回读 %{public}d 条',
      origin, pairs.size, installed, rejected, readBack);
    if (rejected > 0 || (readBack >= 0 && readBack < installed)) {
      this.notice = '登录会话没有全部装入浏览器，页面可能要求重新登录';
    }
  }

  aboutToDisappear(): void { this.active = false; }

  /** 要精确跳到的那一条作业的 id 是否可用（必须是纯数字，别把查询串拼进脚本）。 */
  private jumpable(): boolean { return /^\d+$/.test(this.workId); }

  /** 当前地址是不是那一条作业的页面。 */
  private isTargetWork(loaded: string): boolean {
    return this.jumpable() && loaded.includes('workId=' + this.workId) && !loaded.includes('getAllWork');
  }

  /**
   * 在已经渲染好的列表页里点那一条作业的「查看」。
   *
   * 选择条件收紧到 href **同时**含 `workId=<id>` 与 `workAnswerId=`，并且排除
   * `onclick="javascript:void(0);"`（列表里标题那个锚点就是这样，点了不动）和 `target="_blank"`
   * 的锚点。找不到就什么都不点，只给提示——宁可停在列表页也不点错。
   */
  private clickWorkLink(): void {
    const script: string =
      '(function(){var id="' + this.workId + '";var as=document.querySelectorAll("a[href]");' +
      'for(var i=0;i<as.length;i++){var h=as[i].getAttribute("href")||"";' +
      'var oc=as[i].getAttribute("onclick")||"";var tg=as[i].getAttribute("target")||"";' +
      'if(h.indexOf("workId="+id)>=0&&h.indexOf("workAnswerId=")>=0&&oc.indexOf("void(0)")<0&&tg!=="_blank")' +
      '{as[i].click();return h;}}return "";})()';
    this.controller.runJavaScript(script).then((result: string) => {
      if (!this.active) return;
      const value: string = result.length > 1 && result.startsWith('"') ?
        result.substring(1, result.length - 1) : result;
      hilog.info(DOMAIN, TAG, '精确跳转：%{public}s', value.length > 0 ? value.substring(0, 120) : '未找到锚点');
      if (value.length === 0) this.hint = HINT;
    }).catch((error: BusinessError) => {
      if (!this.active) return;
      hilog.error(DOMAIN, TAG, '精确跳转脚本执行失败，错误码 %{public}d', error.code);
      this.hint = HINT;
    });
  }

  build() {
    Column() {
      if (this.notice) {
        Text(this.notice).fontSize($r('app.float.ui_text_body'))
          .fontColor($r('app.color.ui_text_secondary'))
          .width('100%').padding($r('app.float.ui_space_content'))
          .id('notice-work-web-notice')
      }
      Web({ src: this.url, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (event.request.isMainFrame()) {
            this.failure = `作业页面加载失败（${event.error.getErrorInfo()}，错误码 ${event.error.getErrorCode()}）`;
            hilog.error(DOMAIN, TAG, '作业页面加载失败，主机 %{public}s，错误码 %{public}d',
              hostOf(event.request.getRequestUrl()), event.error.getErrorCode());
          }
        })
        .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
          if (event.request.isMainFrame()) {
            const code: number = event.response.getResponseCode();
            this.failure = code === 401 || code === 403 ?
              `作业页面返回 HTTP ${code}，会话可能已失效，请重新登录` : `作业页面返回 HTTP ${code}`;
            hilog.error(DOMAIN, TAG, '作业页面 HTTP %{public}d，主机 %{public}s',
              code, hostOf(event.request.getRequestUrl()));
          }
        })
        .onPageEnd((event: OnPageEndEvent) => {
          this.loginExpired = isLoginRedirect(event.url);
          if (this.loginExpired) {
            hilog.warn(DOMAIN, TAG, '作业页面落到了登录页，主机 %{public}s', hostOf(event.url));
            return;
          }
          if (this.isTargetWork(event.url)) {
            this.jumped = true; this.hint = '';
            hilog.info(DOMAIN, TAG, '已落到目标作业：主机 %{public}s，含 workId', hostOf(event.url));
            return;
          }
          if (!this.jumpable() || this.jumped || this.attempts > 0) return;
          this.attempts++;
          hilog.info(DOMAIN, TAG, '列表页已就绪，尝试精确跳到 workId %{public}s', this.workId);
          this.clickWorkLink();
          setTimeout(() => {
            if (this.active && !this.jumped && this.hint.length === 0) this.hint = HINT;
          }, JUMP_TIMEOUT_MS);
        })
        .width('100%').layoutWeight(1)
      if (this.failure) {
        Text(this.failure).fontSize($r('app.float.ui_text_body'))
          .fontColor($r('app.color.ui_error'))
          .width('100%').padding($r('app.float.ui_space_page'))
          .id('notice-work-web-failure')
      }
      if (this.loginExpired) {
        Text('会话已失效：页面跳到了服务端登录页，请重新登录后再查看作业')
          .fontSize($r('app.float.ui_text_body'))
          .fontColor($r('app.color.ui_error'))
          .width('100%').padding($r('app.float.ui_space_page'))
          .id('notice-work-web-login')
      }
      if (this.hint) {
        Text(this.hint).fontSize($r('app.float.ui_text_body'))
          .fontColor($r('app.color.ui_text_secondary'))
          .width('100%').padding($r('app.float.ui_space_page'))
          .id('notice-work-web-hint')
      }
    }.width('100%').height(LayoutPolicy.matchParent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.ui_canvas'))
  }
}
