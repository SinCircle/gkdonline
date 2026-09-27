/** 基于 2026-09-26 设备实测 backclazzdata 和学校课程页；不由日期推算学期。 */
import { Course, CourseSemester, CourseTerms, CourseCatalog } from '../data/Models';
import { ApiError, ApiErrorKind } from './errors';

interface RawCourse {
  id?: number | string;
  name?: string;
  teacherfactor?: string;
  sectionId?: number | string;
}

interface RawCourseData {
  data?: RawCourse[];
}

interface RawClass {
  id?: number | string;
  cpi?: number | string;
  beginDate?: string;
  endDate?: string;
  course?: RawCourseData;
}

interface RawChannel {
  content?: RawClass;
}

interface RawCourseResponse {
  result?: number;
  channelList?: RawChannel[];
  hasMore?: boolean;
}

function invalid(message: string): ApiError {
  return new ApiError(ApiErrorKind.PARSE, message);
}

function sourceId(value: number | string | undefined): string {
  if (typeof value === 'number' && Number.isSafeInteger(value)) return value.toString();
  return typeof value === 'string' ? value : '';
}

export function parseCourseList(body: string): Course[] {
  let response: RawCourseResponse;
  try {
    response = JSON.parse(body.trim()) as RawCourseResponse;
  } catch (error) {
    throw invalid('课程接口正文不是有效 JSON');
  }
  if (response === null || typeof response !== 'object' || response.result !== 1 ||
    !Array.isArray(response.channelList)) {
    throw invalid('课程接口未返回成功的 channelList');
  }
  if (response.hasMore === true) {
    throw invalid('课程接口返回了不完整的分页数据，暂不能显示完整课程');
  }
  const courses: Course[] = [];
  for (const channel of response.channelList) {
    const content: RawClass | undefined = channel?.content;
    const data: RawCourse[] | undefined = content?.course?.data;
    if (content === undefined || content === null || data === undefined || !Array.isArray(data) ||
      data.length === 0) {
      throw invalid('课程条目缺少 content.course.data');
    }
    const classId: string = sourceId(content.id);
    const cpi: string = sourceId(content.cpi);
    for (const raw of data) {
      const courseId: string = sourceId(raw?.id);
      if (courseId.length === 0 || classId.length === 0 || typeof raw?.name !== 'string' ||
        raw.name.trim().length === 0) {
        throw invalid('课程条目缺少有效的名称或编号');
      }
      courses.push({
        id: `${classId}:${courseId}:${cpi}`,
        courseId: courseId,
        classId: classId,
        cpi: cpi,
        name: raw.name,
        teacher: typeof raw.teacherfactor === 'string' ? raw.teacherfactor : '',
        sectionId: sourceId(raw.sectionId),
        semester: '',
        beginDate: typeof content.beginDate === 'string' ? content.beginDate : '',
        endDate: typeof content.endDate === 'string' ? content.endDate : '',
      });
    }
  }
  return courses;
}

function attribute(attributes: string, name: string): string {
  const match: RegExpExecArray | null = new RegExp(`\\b${name}\\s*=\\s*["']([^"']*)["']`, 'i')
    .exec(attributes);
  return match === null ? '' : match[1];
}

/** 学期 ID 与名称来自学校课程页真实 selectdd 选项，当前学期来自其 zse_p。 */
export function parseCourseTerms(html: string): CourseTerms {
  const semesters: CourseSemester[] = [];
  const rows: RegExp = /<li\b([^>]*)>([\s\S]*?)<\/li>/gi;
  let match: RegExpExecArray | null = rows.exec(html);
  while (match !== null) {
    const id: string = attribute(match[1], 'sectionId');
    const semesterNum: string = attribute(match[1], 'semesterNum');
    if (attribute(match[1], 'class').split(/\s+/).includes('zse_li') && id.length > 0 &&
      semesterNum.length > 0 && !semesters.some((term: CourseSemester) => term.id === id)) {
      const label: string = match[2].replace(/<[^>]*>/g, '').replace(/&nbsp;|&#160;/g, ' ').trim();
      if (label.length === 0) throw invalid('学校课程页的学期名称为空');
      semesters.push({ id: id, label: label, semesterNum: semesterNum });
    }
    match = rows.exec(html);
  }
  let currentSemesterId: string = '';
  const selected: RegExp = /<p\b([^>]*)>/gi;
  match = selected.exec(html);
  while (match !== null) {
    if (attribute(match[1], 'class').split(/\s+/).includes('zse_p')) {
      const id: string = attribute(match[1], 'sectionId');
      if (semesters.some((term: CourseSemester) => term.id === id)) {
        currentSemesterId = id;
        break;
      }
    }
    match = selected.exec(html);
  }
  if (semesters.length === 0 || currentSemesterId.length === 0) {
    throw invalid('无法识别学校课程页的学期选项，请重试');
  }
  return { semesters: semesters, currentSemesterId: currentSemesterId };
}

export function buildCourseCatalog(body: string, termPage: string): CourseCatalog {
  const courses: Course[] = parseCourseList(body);
  const terms: CourseTerms = parseCourseTerms(termPage);
  for (const course of courses) {
    const term: CourseSemester | undefined = terms.semesters.find(
      (item: CourseSemester) => item.id === course.sectionId);
    if (course.sectionId.length > 0 && term === undefined) {
      throw invalid('课程学期编号不在学校当前返回的学期列表中');
    }
    course.semester = term === undefined ? '' : term.label;
  }
  return { courses: courses, semesters: terms.semesters, currentSemesterId: terms.currentSemesterId };
}

export function filterCourses(courses: Course[], semesterId: string): Course[] {
  if (semesterId.length === 0) return courses;
  return courses.filter((course: Course) => course.sectionId === semesterId);
}
