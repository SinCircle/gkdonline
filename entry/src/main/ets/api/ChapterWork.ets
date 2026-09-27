import { CourseWork } from '../data/WorkModels';
import { CourseResource, ResourceRoute } from '../data/ResourceModels';
import { ApiError, ApiErrorKind } from './errors';
interface WorkProperty { workid: string; title: string; _jobid?: string; }
interface WorkAttachment { type: string; enc: string; jobid: string; property: WorkProperty; }
interface WorkDefaults { knowledgeid: number; courseid: number; clazzId: number; cpi: number; ktoken: string; }
interface WorkCard { attachments: WorkAttachment[]; defaults: WorkDefaults; }

// URL fields are taken from the school's work module and 142 actual chapter responses.
export function chapterWorkItems(html: string, route: ResourceRoute): CourseResource[] {
  const match: RegExpExecArray | null = /mArg\s*=\s*(\{[^\r\n]+\});/.exec(html);
  if (!match) return [];
  const card: WorkCard = JSON.parse(match[1]) as WorkCard;
  const result: CourseResource[] = [];
  for (const a of card.attachments) {
    if (a.type !== 'workid' && a.type !== 'work') continue;
    const d: WorkDefaults = card.defaults;
    if (String(d.courseid) !== route.course.courseId || String(d.clazzId) !== route.course.classId || String(d.knowledgeid) !== route.chapterId || !a.property.workid || !a.enc || !d.ktoken) {
      throw new ApiError(ApiErrorKind.PARSE, '章节测验定位信息缺失或不匹配');
    }
    const work: CourseWork = { id: a.property.workid, title: a.property.title, status: '章节测验', deadlineText: '',
      detailUrl: 'https://mooc.mooc.ucas.edu.cn/mooc-ans/api/work?api=1&workId=' + encodeURIComponent(a.property.workid) +
        '&jobid=' + encodeURIComponent(a.jobid) + '&originJobId=' + encodeURIComponent(a.property._jobid ?? a.jobid) +
        '&needRedirect=true&skipHeader=true&knowledgeid=' + d.knowledgeid.toString() + '&ktoken=' + encodeURIComponent(d.ktoken) +
        '&cpi=' + d.cpi.toString() + '&ut=s&clazzId=' + d.clazzId.toString() + '&type=&enc=' + encodeURIComponent(a.enc) + '&utenc=undefined&mooc2=1&courseid=' + d.courseid.toString() };
    result.push({ id: 'work:' + work.id, name: work.title, type: '章节测验', size: '', creator: '', date: '', folder: false, work: work });
  }
  return result;
}
