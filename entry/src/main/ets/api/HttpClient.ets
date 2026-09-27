/**
 * 全工程唯一的 HTTP 出口。
 *
 * 统一处理 Cookie 注入、UA、超时、指数退避重试，以及 HANDOFF 3.4 要求的
 * 「302 跳登录页 = 会话过期」判定 —— 这个判断只在这里做一次，别处不许自己判。
 *
 * 重定向默认是自动跟的，这里显式关掉（maxRedirects: 0）自己跟，
 * 因为自动跟的话中途那次 302 会被吞掉，我们只能拿到登录页的 200 HTML，
 * 那样就分不清「接口改版」和「登录过期」了。
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionManager } from '../auth/SessionManager';
import { hostOf, resolveUrl } from '../common/UrlUtil';
import { ApiError, ApiErrorKind } from './errors';
import { isLoginRedirect } from './RedirectRules';

const DOMAIN: number = 0x0a01;
const TAG: string = 'HttpClient';

const USER_AGENT: string =
  'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 gkdOnline/1.0';
const CONNECT_TIMEOUT_MS: number = 10000;
const READ_TIMEOUT_MS: number = 20000;
/** 首次 + 重试 2 次，见 HANDOFF 第 6 节。 */
const MAX_ATTEMPTS: number = 3;
const RETRY_BASE_MS: number = 600;
const MAX_REDIRECTS: number = 5;

/** 只重试网络层失败和服务端 5xx。 */
function isRetryable(error: ApiError): boolean {
  return error.kind === ApiErrorKind.NETWORK ||
    (error.kind === ApiErrorKind.HTTP_STATUS && error.status >= 500 && error.status < 600);
}

function headerValue(header: Object, name: string): string {
  const map: Record<string, string> = header as Record<string, string>;
  const target: string = name.toLowerCase();
  for (const key of Object.keys(map)) {
    if (key.toLowerCase() === target) {
      const value: string = map[key];
      return value === undefined ? '' : value;
    }
  }
  return '';
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

export interface HttpResult {
  status: number;
  contentType: string;
  body: string;
  /** 跟完跳转之后的地址。 */
  finalUrl: string;
}

export interface HttpSpec {
  url: string;
  method?: http.RequestMethod;
  body?: string;
  contentType?: string;
  /** 不传则按目标主机从会话里自动挑。 */
  cookie?: string;
}

async function sendOnce(spec: HttpSpec): Promise<HttpResult> {
  let currentUrl: string = spec.url;
  let method: http.RequestMethod = spec.method ?? http.RequestMethod.GET;
  let body: string | undefined = spec.body;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const request: http.HttpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = {};
      headers['User-Agent'] = USER_AGENT;
      headers['Accept'] = '*/*';

      const cookie: string = spec.cookie !== undefined && hostOf(currentUrl) === hostOf(spec.url) ?
        spec.cookie : SessionManager.get().cookieHeaderFor(hostOf(currentUrl));
      if (cookie.length > 0) {
        headers['Cookie'] = cookie;
      }
      if (body !== undefined) {
        headers['Content-Type'] = spec.contentType ?? 'application/x-www-form-urlencoded';
      }

      const options: http.HttpRequestOptions = {
        method: method,
        header: headers,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS,
        maxRedirects: 0,
        expectDataType: http.HttpDataType.STRING,
      };
      if (body !== undefined) {
        options.extraData = body;
      }

      const response: http.HttpResponse = await request.request(currentUrl, options);
      const status: number = response.responseCode;
      const text: string = typeof response.result === 'string' ? response.result : '';
      const contentType: string = headerValue(response.header, 'content-type');

      if (status >= 300 && status < 400) {
        const location: string = headerValue(response.header, 'location');
        if (location.length === 0) {
          throw new ApiError(ApiErrorKind.HTTP_STATUS,
            `服务端返回 ${status} 但没有给 Location`, status, '', contentType, text);
        }
        const nextUrl: string = resolveUrl(currentUrl, location);
        if (isLoginRedirect(nextUrl)) {
          throw ApiError.sessionExpired(`${currentUrl} -> ${nextUrl}`, status, contentType, text);
        }
        if (nextUrl.length === 0) {
          throw new ApiError(ApiErrorKind.HTTP_STATUS,
            `无法解析跳转目标 ${location}`, status, '', contentType, text);
        }
        hilog.info(DOMAIN, TAG, '%{public}d 跳转到主机 %{public}s', status, hostOf(nextUrl));
        currentUrl = nextUrl;
        // 303 和绝大多数 301/302 都要求把后续请求降级成 GET，并且不再带 body。
        if (status === 301 || status === 302 || status === 303) {
          method = http.RequestMethod.GET;
          body = undefined;
        }
        continue;
      }

      if (status >= 400) {
        throw new ApiError(ApiErrorKind.HTTP_STATUS, `请求失败，状态码 ${status}`, status,
          '', contentType, text);
      }

      return {
        status: status,
        contentType: contentType,
        body: text,
        finalUrl: currentUrl,
      };
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      const err: BusinessError = error as BusinessError;
      throw new ApiError(ApiErrorKind.NETWORK,
        `网络请求失败（${err.code}）`, 0, err.message);
    } finally {
      request.destroy();
    }
  }

  throw new ApiError(ApiErrorKind.HTTP_STATUS, `重定向超过 ${MAX_REDIRECTS} 次，已放弃`);
}

/** 发一个请求。网络层失败按指数退避重试，会话过期和解析错误不重试。 */
export async function send(spec: HttpSpec): Promise<HttpResult> {
  const canRetry: boolean = spec.method === undefined || spec.method === http.RequestMethod.GET;
  let lastError: ApiError = new ApiError(ApiErrorKind.NETWORK, '请求未执行');
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      return await sendOnce(spec);
    } catch (error) {
      const err: ApiError = error as ApiError;
      lastError = err;
      if (!canRetry || !isRetryable(err)) {
        throw err;
      }
      hilog.warn(DOMAIN, TAG, '第 %{public}d 次请求失败(%{public}s)，%{public}s',
        attempt, err.kind, err.message);
      if (attempt < MAX_ATTEMPTS) {
        await delay(RETRY_BASE_MS * Math.pow(2, attempt - 1));
      }
    }
  }
  throw lastError;
}
