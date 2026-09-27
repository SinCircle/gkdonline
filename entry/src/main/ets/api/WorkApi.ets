import { fileIo as fs } from '@kit.CoreFileKit';
import { Course } from '../data/Models';
import { CourseWork } from '../data/WorkModels';
import { SessionManager } from '../auth/SessionManager';
import { ApiError, ApiErrorKind } from './errors';
import { transferFile } from './FileTransfer';
import { parseWorkList, workListUrl, workPageInfo } from './WorkParser';

async function readPage(url: string, cacheDir: string): Promise<string> {
  const path: string = cacheDir + '/work-' + Date.now().toString() + '-' + Math.random().toString(36).substring(2) + '.html';
  try {
    await transferFile(url, path, () => {}, () => {}, 8 * 1024 * 1024);
    return fs.readTextSync(path);
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(ApiErrorKind.NETWORK, (error as Error).message);
  } finally { if (fs.accessSync(path)) fs.unlinkSync(path); }
}

export async function fetchCourseWork(course: Course, cacheDir: string): Promise<CourseWork[]> {
  if (!SessionManager.get().loggedIn) throw ApiError.sessionExpired('尚未保存会话凭证');
  const entry: string = 'https://mooc.mooc.ucas.edu.cn/mooc-ans/visit/stucoursemiddle' +
    `?courseid=${course.courseId}&clazzid=${course.classId}&vc=1&cpi=${course.cpi}&ismooc2=1&v=2`;
  const html: string = await readPage(entry, cacheDir);
  const url: string = workListUrl(html, course);
  const list: string = await readPage(url, cacheDir);
  const items: CourseWork[] = parseWorkList(list, course);
  const info = workPageInfo(list);
  if (info.current !== 1) throw new ApiError(ApiErrorKind.PARSE, '作业首页页码不匹配');
  for (let page: number = 2; page <= info.total; page++) {
    const body: string = await readPage(url + `&pageNum=${page}&status=0&topicId=0`, cacheDir);
    const nextInfo = workPageInfo(body);
    if (nextInfo.current !== page || nextInfo.total !== info.total) throw new ApiError(ApiErrorKind.PARSE, '作业分页不一致，请刷新');
    for (const item of parseWorkList(body, course)) {
      if (items.some((prior: CourseWork) => prior.id === item.id)) throw new ApiError(ApiErrorKind.PARSE, '作业分页条目重复');
      items.push(item);
    }
  }
  return items;
}
