import { Course } from '../data/Models';
import { ChapterCatalog, ChapterCard, CourseResource, ResourcePage, ResourceRoute } from '../data/ResourceModels';
import { SessionManager } from '../auth/SessionManager';
import { send } from './HttpClient';
import { ApiError, ApiErrorKind } from './errors';
import { parseChapters, parseCourseResources, parseChapterCard } from './ResourceParser';
import { chapterWorkItems } from './ChapterWork';

const ORIGIN: string = 'https://mooc.mooc.ucas.edu.cn';

function checkSession(): void {
  if (!SessionManager.get().loggedIn) throw ApiError.sessionExpired('尚未保存会话凭证');
}

export function chapterUrl(course: Course): string {
  return ORIGIN + `/mooc2-ans/mycourse/studentcourse?courseid=${course.courseId}&clazzid=${course.classId}&cpi=${course.cpi}`;
}

export function courseResourcesUrl(route: ResourceRoute, page: number = 1): string {
  const course: Course = route.course;
  return ORIGIN + `/mooc2-ans/coursedata/stu-datalist?courseid=${course.courseId}&clazzid=${course.classId}` +
    `&cpi=${course.cpi}&dataId=${route.folderId}&pages=${page}&type=1&parent=${route.parentId}&ut=s&t=0&enc=${encodeURIComponent(route.enc)}`;
}

export function chapterResourcesUrl(route: ResourceRoute, page: number): string {
  const course: Course = route.course;
  return ORIGIN + `/mooc-ans/knowledge/cards?clazzid=${course.classId}&courseid=${course.courseId}` +
    `&knowledgeid=${route.chapterId}&num=${page}&ut=s&cpi=${course.cpi}&mooc2=1&isMicroCourse=false&editorPreview=0`;
}

export async function fetchChapters(course: Course): Promise<ChapterCatalog> {
  checkSession();
  return parseChapters((await send({ url: chapterUrl(course) })).body, course.courseId);
}

export async function fetchCourseResources(route: ResourceRoute): Promise<ResourcePage> {
  checkSession();
  const first: ResourcePage = parseCourseResources((await send({ url: courseResourcesUrl(route) })).body, route.course.courseId);
  if (first.totalPages > 100) throw new ApiError(ApiErrorKind.PARSE, '资料分页数量异常，尚未取得完整列表');
  for (let page: number = 2; page <= first.totalPages; page++) {
    checkSession();
    const next: ResourcePage = parseCourseResources((await send({ url: courseResourcesUrl(route, page) })).body, route.course.courseId);
    first.items = first.items.concat(next.items);
  }
  return first;
}

export async function fetchChapterResources(route: ResourceRoute): Promise<ResourcePage> {
  const items: CourseResource[] = [];
  const cardIds: string[] = [];
  for (let page: number = 0; page < 100; page++) {
    checkSession();
    const html: string = (await send({ url: chapterResourcesUrl(route, page) })).body;
    const card: ChapterCard = parseChapterCard(html, route.chapterId);
    // 真实样本的下一页以 cardId="" 表示结束；不能用 attachments 为空判断结束。
    if (card.cardId.length === 0) return { items: items, enc: '', totalPages: 1 };
    if (cardIds.includes(card.cardId)) throw new ApiError(ApiErrorKind.PARSE, '章节分页重复，尚未取得完整资源列表');
    cardIds.push(card.cardId);
    items.push(...card.items);
    items.push(...chapterWorkItems(html, route));
  }
  throw new ApiError(ApiErrorKind.PARSE, '章节分页数量异常，尚未取得完整资源列表');
}
