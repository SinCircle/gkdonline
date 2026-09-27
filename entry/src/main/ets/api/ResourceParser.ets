/** 仅解析 2026-09-26 设备取回的学校页面，不执行网页脚本或学习记录接口。 */
import { Chapter, ChapterCatalog, CourseResource, ResourcePage, ChapterCard } from '../data/ResourceModels';
import { ApiError, ApiErrorKind } from './errors';

function invalid(message: string): ApiError { return new ApiError(ApiErrorKind.PARSE, message); }

function decode(text: string): string {
  return text.replace(/&#(x[\da-f]+|\d+);/gi, (_: string, code: string): string => {
    const value: number = code.toLowerCase().startsWith('x') ? parseInt(code.substring(1), 16) : parseInt(code, 10);
    return value >= 0 && value <= 0x10ffff ? String.fromCodePoint(value) : '';
  }).replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
}

function plain(text: string): string { return decode(text.replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim(); }

function attr(tag: string, key: string): string {
  const match: RegExpExecArray | null = new RegExp(`\\b${key}\\s*=\\s*(["'])([\\s\\S]*?)\\1`, 'i').exec(tag);
  return match === null ? '' : decode(match[2]);
}

function hidden(html: string, id: string): string {
  const tags: RegExp = /<input\b[^>]*>/gi;
  let match: RegExpExecArray | null = tags.exec(html);
  while (match !== null) {
    if (attr(match[0], 'id') === id) return attr(match[0], 'value');
    match = tags.exec(html);
  }
  return '';
}

export function parseChapters(html: string, courseId: string): ChapterCatalog {
  if (!html.includes('id="fanyaChapter"') || hidden(html, 'courseId') !== courseId) {
    throw invalid('章节页面结构或课程编号不匹配');
  }
  const chapters: Chapter[] = [];
  const rows: RegExp = /<div\b[^>]*class="chapter_item"[^>]*>/g;
  let match: RegExpExecArray | null = rows.exec(html);
  while (match !== null) {
    const next: RegExpExecArray | null = rows.exec(html);
    const body: string = html.substring(match.index + match[0].length, next?.index ?? html.length);
    const link: RegExpExecArray | null = /<a\b[^>]*class="clicktitle"[^>]*>([\s\S]*?)<\/a>/.exec(body);
    const id: string = attr(match[0], 'id').replace(/^cur/, '');
    const numberMatch: RegExpExecArray | null = /class="catalog_sbar"[^>]*>([^<]+)</.exec(body);
    const groupNumber: RegExpExecArray | null = /class="catalog_num[^"]*"[\s\S]*?<em[^>]*>([^<]+)</.exec(body);
    const number: string = plain(numberMatch?.[1] ?? groupNumber?.[1] ?? '');
    const title: string = id.length > 0 ? attr(match[0], 'title') : plain(link?.[1] ?? '');
    if (title.length === 0 || number.length === 0 || (id.length > 0 && !/^\d+$/.test(id))) {
      throw invalid('章节条目缺少名称、序号或有效编号');
    }
    chapters.push({ id: id.length > 0 ? id : `group:${number}`, number: number, title: title, group: id.length === 0 });
    match = next;
  }
  if (chapters.length === 0 && !html.includes('暂无章节内容')) throw invalid('无法识别章节列表，不能当作空目录');
  return { chapters: chapters };
}

function cell(html: string, name: string): string {
  const match: RegExpExecArray | null = new RegExp(`<li[^>]*class="${name}"[^>]*>([\\s\\S]*?)<\\/li>`).exec(html);
  return plain(match?.[1] ?? '');
}

export function parseCourseResources(html: string, courseId: string): ResourcePage {
  if (!html.includes('id="fanyaData"') || hidden(html, 'courseId') !== courseId) {
    throw invalid('资料页面结构或课程编号不匹配');
  }
  const start: number = html.indexOf('<div class="dataBody">');
  const end: number = html.indexOf('<div class="pageDiv">', start);
  if (start < 0 || end < start) throw invalid('无法识别资料列表');
  const body: string = html.substring(start, end);
  const items: CourseResource[] = [];
  const rows: RegExp = /<ul\b[^>]*class="dataBody_td"[^>]*>/g;
  let match: RegExpExecArray | null = rows.exec(body);
  while (match !== null) {
    const next: RegExpExecArray | null = rows.exec(body);
    const fragment: string = body.substring(match.index, next?.index ?? body.length);
    const id: string = attr(match[0], 'id');
    const name: string = attr(match[0], 'dataName');
    const type: string = attr(match[0], 'type');
    const download: RegExpExecArray | null = /href=(["'])([^"']*\/coursedata\/downloadData\?[^"']*)\1/.exec(fragment);
    if (!/^\d+$/.test(id) || name.length === 0 || type.length === 0) throw invalid('资料条目字段缺失');
    items.push({ id: id, name: name, type: type, folder: type === 'afolder',
      size: cell(fragment, 'dataBody_size_stu'), creator: cell(fragment, 'dataBody_creater_stu'),
      date: cell(fragment, 'dataBody_time_stu'), downloadUrl: download === null ? '' : decode(download[2]) });
    match = next;
  }
  if (items.length === 0 && !body.includes('暂无文件')) throw invalid('资料列表结构变化，不能当作空列表');
  const total: number = Number(hidden(html, 'totalPages'));
  if (!Number.isInteger(total) || total < 1) throw invalid('资料分页字段缺失');
  return { items: items, enc: hidden(html, 'enc'), totalPages: total };
}

interface AttachmentProperty { name?: string; hsize?: string; type?: string; objectid?: string; }
interface Attachment { type?: string; aid?: number; property?: AttachmentProperty; objectId?: string; }
interface CardData { attachments?: Attachment[]; }

export function parseChapterCard(html: string, chapterId: string): ChapterCard {
  if (hidden(html, 'knowledgeId') !== chapterId || !html.includes('id="cardId"')) {
    throw invalid('章节资源页面结构或章节编号不匹配');
  }
  const cardId: string = hidden(html, 'cardId');
  if (cardId.length === 0) return { cardId: '', items: [] };
  const match: RegExpExecArray | null = /\bmArg\s*=\s*(\{[^\r\n]*\})\s*;/.exec(html);
  if (match === null) throw invalid('章节资源清单缺失');
  let data: CardData;
  try { data = JSON.parse(match[1]) as CardData; } catch (error) { throw invalid('章节资源清单无法解析'); }
  if (!Array.isArray(data.attachments)) throw invalid('章节资源 attachments 字段缺失');
  const items: CourseResource[] = [];
  for (const attachment of data.attachments) {
    // 作业不是可下载文件；真实学校样本的类型为 workid。
    if (attachment.type === 'work' || attachment.type === 'workid') continue;
    const property: AttachmentProperty | undefined = attachment.property;
    if (typeof property?.name !== 'string' || property.name.length === 0) throw invalid('章节资源缺少名称');
    const id: string = attachment.objectId ?? property.objectid ?? attachment.aid?.toString() ?? '';
    if (id.length === 0) throw invalid('章节资源缺少编号');
    items.push({ id: `${cardId}:${id}`, name: property.name, type: property.type ?? attachment.type ?? '',
      size: property.hsize ?? '', creator: '', date: '', folder: false, objectId: attachment.objectId ?? property.objectid ?? '' });
  }
  return { cardId: cardId, items: items };
}
