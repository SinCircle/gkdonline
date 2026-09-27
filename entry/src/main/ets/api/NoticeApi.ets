import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Notice } from '../data/Models';
import { SessionManager } from '../auth/SessionManager';
import { ApiError } from './errors';
import { HttpResult, send } from './HttpClient';
import { cleanText, parseHtml } from './WorkHtml';

const ORIGIN: string = 'https://notice.mooc.ucas.edu.cn';
const AJAX_HEADERS: Record<string, string> = {
  'X-Requested-With': 'XMLHttpRequest',
  'Origin': ORIGIN,
  'Referer': ORIGIN + '/pc/notice/myNotice',
};
const DOMAIN: number = 0x0a01;
const TAG: string = 'NoticeApi';

export class NoticeAccessError extends Error {
  readonly status: number;
  readonly response: string;
  constructor(status: number, response: string, reason: string) {
    super(reason);
    this.status = status;
    this.response = response;
  }
}

export interface NoticePage {
  list: Notice[];
  lastGetId: string;
  lastPage: boolean;
  status: number;
  responseFirst200: string;
}

export interface NoticeSource {
  load(lastValue?: string): Promise<NoticePage>;
}

function stringField(item: Record<string, Object>, name: string): string {
  return typeof item[name] === 'string' ? item[name] as string : '';
}

/** 日志里的一行摘要：折掉换行，只留前 200 字。 */
function flatBody(body: string): string {
  return body.replace(/[\r\n]+/g, ' ').trim().substring(0, 200);
}

function workUrl(attachment: string): string {
  if (!attachment) return '';
  try {
    const items: Array<Record<string, Object>> = JSON.parse(attachment) as Array<Record<string, Object>>;
    if (!Array.isArray(items)) return '';
    for (const item of items) {
      const web: Record<string, Object> = item['att_web'] as Record<string, Object>;
      const url: string = web ? stringField(web, 'url') : '';
      if (/^https?:\/\/mooc\.mooc\.ucas\.edu\.cn\/mooc-ans\/examApi\/intoexamorwork\?/.test(url)) return url;
    }
  } catch (_) { /* A notice may have no usable attachment. */ }
  return '';
}

// 服务端通知正文模板里带了一句没有信息量的「你的作业」标签。
// 实测它可能独占一行，也可能直接接在下一句前面（如「你的作业还有24个小时就要结束…」），
// 所以按行首剥离，而不是只丢整行。
const NOISE_TOKENS: string[] = ['你的作业'];

function dropNoiseLines(text: string): string {
  if (!text) return text;
  const kept: string[] = [];
  for (const raw of text.split(/\r\n|\r|\n/)) {
    let line: string = raw.trim();
    for (const token of NOISE_TOKENS) {
      if (line === token) { line = ''; break; }
      if (line.startsWith(token)) { line = line.substring(token.length).trim(); break; }
    }
    if (line.length > 0) kept.push(line);
  }
  return kept.join('\n');
}

function noticeFrom(item: Record<string, Object>): Notice {
  const uuid: string = stringField(item, 'uuid');
  const html: string = stringField(item, 'rtf_content');
  const attachment: string = stringField(item, 'attachment');
  return {
    id: uuid,
    uuid: uuid,
    title: stringField(item, 'title'),
    content: dropNoiseLines(stringField(item, 'content')),
    time: stringField(item, 'ftime') || stringField(item, 'sendTime'),
    sender: stringField(item, 'createrName'),
    read: item['isread'] === 1,
    bodyText: dropNoiseLines(html ? cleanText(parseHtml(html)) : stringField(item, 'content')),
    workUrl: workUrl(attachment),
  };
}

function parseResponse(response: HttpResult): Record<string, Object> {
  const raw: string = response.body.trim();
  let body: Record<string, Object>;
  try { body = JSON.parse(raw) as Record<string, Object>; }
  catch (_) { throw new NoticeAccessError(response.status, raw.substring(0, 200), '通知接口返回了非 JSON 内容'); }
  if (body['status'] !== true) {
    const reason: string = stringField(body, 'errorMsg') || stringField(body, 'msg') || '通知接口未返回成功状态';
    throw new NoticeAccessError(response.status, raw.substring(0, 200), reason);
  }
  return body;
}

export class SchoolNoticeSource implements NoticeSource {
  async load(lastValue: string = ''): Promise<NoticePage> {
    if (!SessionManager.get().loggedIn) throw ApiError.sessionExpired('请先登录后查看通知');
    const year: string = new Date().getFullYear().toString();
    const form: string = 'type=2&notice_type=&lastValue=' + encodeURIComponent(lastValue) +
      '&sort=&folderUUID=&kw=&startTime=&endTime=&gKw=&gName=&year=' + year +
      '&tag=&fidsCode=&queryFolderNoticePrevYear=0&filterSenderPuids=&filterTags=';
    const response: HttpResult = await send({ url: ORIGIN + '/pc/notice/getNoticeList',
      method: http.RequestMethod.POST, body: form, contentType: 'application/x-www-form-urlencoded',
      headers: AJAX_HEADERS });
    hilog.info(DOMAIN, TAG, '通知列表 HTTP %{public}d，响应 %{public}d 字符，前 200 字：%{public}s',
      response.status, response.body.length, flatBody(response.body));
    const body: Record<string, Object> = parseResponse(response);
    const notices: Record<string, Object> = body['notices'] as Record<string, Object>;
    const rawList: Array<Record<string, Object>> = notices?.['list'] as Array<Record<string, Object>>;
    if (!notices || !Array.isArray(rawList)) {
      throw new NoticeAccessError(response.status, response.body.substring(0, 200), '通知列表缺少 notices.list');
    }
    const list: Notice[] = rawList.map((item: Record<string, Object>) => noticeFrom(item));
    if (list.some((item: Notice) => !item.uuid)) {
      throw new NoticeAccessError(response.status, response.body.substring(0, 200), '通知缺少 uuid');
    }
    return { list: list, lastGetId: stringField(notices, 'lastGetId'),
      lastPage: notices['lastPage'] === 1, status: response.status,
      responseFirst200: response.body.substring(0, 200) };
  }
}

export async function fetchNoticeDetail(uuid: string): Promise<Notice> {
  if (!SessionManager.get().loggedIn) throw ApiError.sessionExpired('请先登录后查看通知');
  const url: string = ORIGIN + '/pc/notice/' + encodeURIComponent(uuid) + '/getNoticeDetail?sendTag=0';
  const response: HttpResult = await send({ url: url, headers: AJAX_HEADERS });
  hilog.info(DOMAIN, TAG, '通知详情 HTTP %{public}d，响应 %{public}d 字符，前 200 字：%{public}s',
    response.status, response.body.length, flatBody(response.body));
  const body: Record<string, Object> = parseResponse(response);
  const msg: Record<string, Object> = body['msg'] as Record<string, Object>;
  if (!msg || !stringField(msg, 'uuid')) {
    throw new NoticeAccessError(response.status, response.body.substring(0, 200), '通知详情缺少 msg.uuid');
  }
  return noticeFrom(msg);
}
