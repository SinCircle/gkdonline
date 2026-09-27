import { CourseCatalog, Notice } from './Models';
import { fetchCourseCatalog } from '../api/CourseApi';
import { SchoolNoticeSource, NoticeSource } from '../api/NoticeApi';

export const USING_SAMPLE_DATA: boolean = false;
export const USING_SAMPLE_NOTICES: boolean = false;

export async function loadCourses(): Promise<CourseCatalog> {
  return fetchCourseCatalog();
}

export async function loadNotices(): Promise<Notice[]> {
  const source: NoticeSource = new SchoolNoticeSource();
  return source.load();
}
