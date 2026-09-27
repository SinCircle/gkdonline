/**
 * 统一的错误类型。
 *
 * 只用一个 ApiError，靠 kind 区分，不做一层继承树 —— 调用方目前只关心
 * 「是不是会话过期」，其余都归到「失败了，原因是什么」。
 */

export enum ApiErrorKind {
  /** 会话过期。全工程唯一判定点在 api/HttpClient，其余地方只处理，不判定。 */
  SESSION_EXPIRED = 'session-expired',
  /** 连不上 / 超时等网络层失败。 */
  NETWORK = 'network',
  /** 连上了但 HTTP 状态码不是 2xx。 */
  HTTP_STATUS = 'http-status',
  /** 拿到了响应但内容不是预期的 JSON。 */
  PARSE = 'parse',
}

export class ApiError extends Error {
  readonly kind: ApiErrorKind;
  /** HTTP 状态码，非 HTTP 层失败时为 0。 */
  readonly status: number;
  /** 便于排查的补充信息，如跳转目标、响应片段。不面向用户。 */
  readonly detail: string;
  /** 原始 HTTP 响应，供 M1 连接自检查看；不在日志中输出 Cookie。 */
  readonly contentType: string;
  readonly responseBody: string;

  constructor(kind: ApiErrorKind, message: string, status: number = 0, detail: string = '',
    contentType: string = '', responseBody: string = '') {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.status = status;
    this.detail = detail;
    this.contentType = contentType;
    this.responseBody = responseBody;
  }

  static sessionExpired(detail: string, status: number = 302,
    contentType: string = '', responseBody: string = ''): ApiError {
    return new ApiError(ApiErrorKind.SESSION_EXPIRED, '登录状态已失效，请重新登录',
      status, detail, contentType, responseBody);
  }
}

/** 面向用户的一句话说明。 */
export function describeApiError(error: ApiError): string {
  switch (error.kind) {
    case ApiErrorKind.SESSION_EXPIRED:
      return '登录状态已失效，请重新登录';
    case ApiErrorKind.NETWORK:
      return `网络请求失败：${error.message}`;
    case ApiErrorKind.HTTP_STATUS:
      return `服务端返回 ${error.status}`;
    case ApiErrorKind.PARSE:
      return '接口返回的内容解析不了，接口可能已变更';
    default:
      return error.message;
  }
}
