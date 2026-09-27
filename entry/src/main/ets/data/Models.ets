export interface Course {
  id: string;
  courseId: string;
  classId: string;
  cpi: string;
  name: string;
  teacher: string;
  unfinishedWorkCount?: number;
  sectionId: string;
  semester: string;
  beginDate: string;
  endDate: string;
}

export interface CourseSemester {
  id: string;
  label: string;
  semesterNum: string;
}

export interface CourseTerms {
  semesters: CourseSemester[];
  currentSemesterId: string;
}

export interface CourseCatalog {
  courses: Course[];
  semesters: CourseSemester[];
  currentSemesterId: string;
}

export interface Notice {
  id: string;
  title: string;
  content: string;
  time: string;
  read: boolean;
}
