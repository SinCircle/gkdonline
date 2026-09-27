/**
 * 课程接口。
 *
 * 主选域名及正文结构已经过设备实测；学期名称读取学校课程页的真实选项。
 */

import { SessionManager } from '../auth/SessionManager';
import { send, HttpResult } from './HttpClient';
import { ApiError, describeApiError } from './errors';
import { CourseCatalog } from '../data/Models';
import { buildCourseCatalog, parseCourseList } from './CourseParser';

const COURSE_LIST_PATH: string = '/mycourse/backclazzdata';
/** ServerHost.js 实测确认的国科大 mooc1 镜像，课程接口主选。 */
const UCAS_MOOC_ORIGIN: string = 'https://mooc.mooc.ucas.edu.cn';
/** 超星通用接口主机，仅作对照。 */
const CHAOXING_REFERENCE_ORIGIN: string = 'https://mooc1-api.chaoxing.com';

const PREVIEW_LIMIT: number = 300;

export interface EndpointProbe {
  url: string;
  ok: boolean;
  status: number;
  contentType: string;
  /** 完整正文能被识别为成功的课程 JSON，不依赖 Content-Type。 */
  recognized: boolean;
  /** 响应正文前若干字符，用来肉眼判断是不是登录页 / 是不是 JSON。 */
  preview: string;
  /** 失败原因，成功时为空串。 */
  note: string;
}

/** 按「国科大镜像 → 超星通用对照 → 登录后落地域」的顺序探测。 */
export function candidateCourseEndpoints(): string[] {
  const result: string[] = [UCAS_MOOC_ORIGIN + COURSE_LIST_PATH, CHAOXING_REFERENCE_ORIGIN + COURSE_LIST_PATH];
  const origin: string = SessionManager.get().loginOrigin;
  if (origin.length > 0 && result.indexOf(origin + COURSE_LIST_PATH) < 0) {
    result.push(origin + COURSE_LIST_PATH);
  }
  return result;
}

/** 逐个候选地址请求课程列表，把原始证据带回来。不解析、不猜测。 */
export async function probeCourseList(): Promise<EndpointProbe[]> {
  const probes: EndpointProbe[] = [];
  for (const url of candidateCourseEndpoints()) {
    try {
      const result: HttpResult = await send({ url: url });
      let recognized: boolean = false;
      try {
        parseCourseList(result.body);
        recognized = true;
      } catch (error) {
        // 自检保留 HTTP 原始信息；无法识别的正文不算校验通过。
      }
      probes.push({
        url: url,
        ok: true,
        status: result.status,
        contentType: result.contentType,
        recognized: recognized,
        preview: result.body.substring(0, PREVIEW_LIMIT),
        note: '',
      });
    } catch (error) {
      const err: ApiError = error as ApiError;
      probes.push({
        url: url,
        ok: false,
        status: err.status,
        contentType: err.contentType,
        recognized: false,
        preview: err.responseBody.substring(0, PREVIEW_LIMIT),
        note: `${describeApiError(err)}${err.detail.length > 0 ? `（${err.detail.substring(0, 120)}）` : ''}`,
      });
    }
  }
  return probes;
}

export async function fetchCourseCatalog(): Promise<CourseCatalog> {
  if (!SessionManager.get().loggedIn) {
    throw ApiError.sessionExpired('本地没有已登录会话');
  }
  const response: HttpResult = await send({ url: UCAS_MOOC_ORIGIN + COURSE_LIST_PATH });
  const termPage: HttpResult = await send({ url: 'https://mooc.ucas.edu.cn/courselist/mycourse' });
  return buildCourseCatalog(response.body, termPage.body);
}
