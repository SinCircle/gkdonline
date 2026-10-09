/**
 * 课程接口。
 *
 * 主选域名及正文结构已经过设备实测；学期名称读取学校课程页的真实选项。
 */

import { SessionManager } from '../auth/SessionManager';
import { send, HttpResult } from './HttpClient';
import { ApiError } from './errors';
import { CourseCatalog } from '../data/Models';
import { buildCourseCatalog } from './CourseParser';

const COURSE_LIST_PATH: string = '/mycourse/backclazzdata';
/** ServerHost.js 实测确认的国科大 mooc1 镜像，课程接口主选。 */
const UCAS_MOOC_ORIGIN: string = 'https://mooc.mooc.ucas.edu.cn';

export async function fetchCourseCatalog(): Promise<CourseCatalog> {
  if (!SessionManager.get().loggedIn) {
    throw ApiError.sessionExpired('本地没有已登录会话');
  }
  const response: HttpResult = await send({ url: UCAS_MOOC_ORIGIN + COURSE_LIST_PATH });
  const termPage: HttpResult = await send({ url: 'https://mooc.ucas.edu.cn/courselist/mycourse' });
  return buildCourseCatalog(response.body, termPage.body);
}
