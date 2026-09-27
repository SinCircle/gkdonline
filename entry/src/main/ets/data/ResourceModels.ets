import { Course } from './Models';
import { CourseWork } from './WorkModels';

export interface Chapter {
  id: string;
  number: string;
  title: string;
  group: boolean;
}

export interface ChapterCatalog { chapters: Chapter[]; }

export interface CourseResource {
  work?: CourseWork;
  id: string;
  name: string;
  type: string;
  size: string;
  creator: string;
  date: string;
  folder: boolean;
  downloadUrl?: string;
  objectId?: string;
}

export interface ResourcePage {
  items: CourseResource[];
  enc: string;
  totalPages: number;
}

export interface ResourceRoute {
  course: Course;
  title: string;
  chapterId: string;
  folderId: string;
  parentId: string;
  enc: string;
}

export interface ChapterCard {
  cardId: string;
  items: CourseResource[];
}
