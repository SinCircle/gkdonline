import { Notice } from '../data/Models';
import { SessionManager } from '../auth/SessionManager';
import { ApiError } from './errors';
import { send } from './HttpClient';

export class NoticeAccessError extends Error {
  readonly status: number;
  readonly response: string;
  constructor(status: number, response: string, reason: string) {
    super(reason);
    this.status = status;
    this.response = response;
  }
}

export interface NoticeSource {
  load(): Promise<Notice[]>;
}

// The four APK paths were probed on-device. The list endpoint currently returns
// result=0 with an IP allowlist rejection. Keep the transport seam for a later
// response sample; never infer a list schema from an error payload.
export class SchoolNoticeSource implements NoticeSource {
  async load(): Promise<Notice[]> {
    if (!SessionManager.get().loggedIn) throw ApiError.sessionExpired('请先登录后查看通知');
    const cookie: string = SessionManager.get().cookieHeaderFor('mooc.mooc.ucas.edu.cn');
    const uid: string = /(?:^|;\s*)_uid=(\d+)/.exec(cookie)?.[1] ?? '';
    const url: string = 'https://notice.chaoxing.com/apis/notice/myNotices_v2?' +
      (uid ? 'puid=' + uid + '&fid=35014' : 'fid=35014');
    const response = await send({ url: url });
    const raw: string = response.body.trim();
    let body: Record<string, Object>;
    try { body = JSON.parse(raw) as Record<string, Object>; }
    catch (_) { throw new NoticeAccessError(response.status, raw.substring(0, 300), '通知接口返回了非 JSON 内容'); }
    if (body['result'] !== 1) {
      const message: string = typeof body['errorMsg'] === 'string' ? body['errorMsg'] as string : '未返回可用通知数据';
      throw new NoticeAccessError(response.status, raw.substring(0, 300), message);
    }
    // No successful sample exists yet. Do not fabricate title, time or read flags.
    throw new NoticeAccessError(response.status, raw.substring(0, 300), '通知响应结构尚未验证');
  }
}
