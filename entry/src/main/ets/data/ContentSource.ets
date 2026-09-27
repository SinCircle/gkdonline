import { CourseCatalog } from './Models';
import { fetchCourseCatalog } from '../api/CourseApi';
import { SchoolNoticeSource, NoticeSource, NoticePage } from '../api/NoticeApi';

export const USING_SAMPLE_DATA: boolean = false;
export const USING_SAMPLE_NOTICES: boolean = false;

export async function loadCourses(): Promise<CourseCatalog> {
  return fetchCourseCatalog();
}

export async function loadNotices(lastValue: string = ''): Promise<NoticePage> {
  const source: NoticeSource = new SchoolNoticeSource();
  return source.load(lastValue);
}
