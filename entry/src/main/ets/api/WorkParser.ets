import { Course } from '../data/Models';
import { CourseWork } from '../data/WorkModels';
import { ApiError, ApiErrorKind } from './errors';

function invalid(message: string): ApiError { return new ApiError(ApiErrorKind.PARSE, message); }
function decode(text: string): string {
  return text.replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
}
function plain(text: string): string { return decode(text.replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim(); }
function hidden(html: string, key: string): string {
  const match: RegExpExecArray | null = new RegExp(`<input[^>]*id="${key}"[^>]*value="([^"]*)"`).exec(html);
  return decode(match?.[1] ?? '');
}

/** Parameter names and workEnc come from the school's actual course-stu.js and entry page. */
export function workListUrl(html: string, course: Course): string {
  if (hidden(html, 'courseid') !== course.courseId || hidden(html, 'clazzid') !== course.classId) throw invalid('作业入口课程编号不匹配');
  if (!html.includes('data-url="/mooc-ans/mooc2/work/list"')) throw invalid('课程未提供已识别的作业入口');
  const enc: string = hidden(html, 'workEnc');
  if (!enc) throw invalid('作业入口签名缺失');
  return 'https://mooc.mooc.ucas.edu.cn/mooc-ans/mooc2/work/list' +
    `?courseId=${course.courseId}&classId=${course.classId}&cpi=${course.cpi}&ut=s` +
    `&t=${encodeURIComponent(hidden(html, 't'))}&stuenc=${encodeURIComponent(hidden(html, 'enc'))}&enc=${encodeURIComponent(enc)}`;
}

export function parseWorkList(html: string, course: Course): CourseWork[] {
  if (!html.includes('<title>作业列表</title>') || hidden(html, 'courseId') !== course.courseId ||
    hidden(html, 'classId') !== course.classId) throw invalid('未取得可识别的课程作业列表');
  const items: CourseWork[] = [];
  const rows: RegExp = /<li\b[^>]*onclick="goTask\(this\);"[^>]*>([\s\S]*?)<\/li>/g;
  let match: RegExpExecArray | null = rows.exec(html);
  while (match !== null) {
    const url: string = decode(/\bdata="([^"]+)"/.exec(match[0])?.[1] ?? '');
    const id: string = /[?&]workId=(\d+)/.exec(url)?.[1] ?? '';
    const title: string = plain(/<p\b[^>]*class="overHidden2 fl"[^>]*>([\s\S]*?)<\/p>/.exec(match[1])?.[1] ?? '');
    const status: string = plain(/<p\b[^>]*class="status fl"[^>]*>([\s\S]*?)<\/p>/.exec(match[1])?.[1] ?? '');
    const deadline: string = plain(/<div\b[^>]*class="time[^"\r\n]*"[^>]*>([\s\S]*?)<\/div>/.exec(match[1])?.[1] ?? '');
    if (!id || !title || !status || items.some((item: CourseWork) => item.id === id)) throw invalid('作业条目字段缺失或编号重复');
    items.push({ id: id, title: title, status: status, deadlineText: deadline, detailUrl: url });
    match = rows.exec(html);
  }
  if (items.length === 0 && (!html.includes('class="null-data"') || !html.includes('暂无作业'))) {
    throw invalid('作业列表结构变化，不能当成空列表');
  }
  workPageInfo(html);
  return items;
}

export interface WorkPageInfo { current: number; total: number; }
export function workPageInfo(html: string): WorkPageInfo {
  if (/\$\("#page"\)\.html\(""\)/.test(html)) return { current: 1, total: 1 };
  const pagination: RegExpExecArray | null = /\$\("#page"\)\.paging\(\{\s*nowPage\s*:\s*(\d+),\s*pageNum\s*:\s*(\d+)/.exec(html);
  if (!pagination) throw invalid('作业分页结构尚未识别，无法确认列表完整');
  const current: number = Number(pagination[1]);
  const total: number = Number(pagination[2]);
  if (current < 1 || total < current || total > 100) throw invalid('作业分页数量异常');
  return { current: current, total: total };
}
