/** 资源接口只读探测。参数组合是待验证线索，HTTP 200 不等于业务可用。 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Course } from '../data/Models';
import { EndpointProbe, fetchCourseCatalog } from './CourseApi';
import { send, HttpResult } from './HttpClient';
import { ApiError } from './errors';
import { chapterUrl } from './ResourceApi';

interface ProbeTarget { label: string; url: string; }
interface ProbeEvidence {
  id: string;
  label: string;
  url: string;
  status: number;
  contentType: string;
  finalUrl: string;
  errorKind: string;
  note: string;
  bytes: number;
  bodyFile: string;
  preview: string;
}

function writeText(path: string, body: string): number {
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try {
    if (body.length === 0) return 0;
    const expected: number = new util.TextEncoder().encodeInto(body).length;
    const written: number = fs.writeSync(file.fd, body);
    if (written !== expected) throw new Error('探测正文没有完整写入');
    return written;
  } finally {
    fs.closeSync(file);
  }
}

function targets(course: Course): ProbeTarget[] {
  const mirrors: string[] = ['https://mooc.mooc.ucas.edu.cn',
    'https://mooc1.mooc.ucas.edu.cn', 'https://cs.mooc.ucas.edu.cn'];
  const result: ProbeTarget[] = [
    { label: 'verified-chapters', url: chapterUrl(course) },
    { label: 'verified-course-resources', url: mirrors[0] +
      `/mooc2-ans/coursedata/stu-datalist?courseid=${course.courseId}&clazzid=${course.classId}&cpi=${course.cpi}` },
  ];
  const routes: ProbeTarget[] = [
    { label: 'chapterlist', url: `/chapterlist?courseid=${course.courseId}&clazzid=${course.classId}&cpi=${course.cpi}` },
    { label: 'gas-course', url: `/gas/course?id=${course.courseId}&courseid=${course.courseId}&clazzid=${course.classId}` },
    { label: 'cloud-fileList', url: `/cloudApi/fileList?courseId=${course.courseId}&classId=${course.classId}` },
    { label: 'student-courseware', url: `/page/ppt/mobile/studentCoursewareList?courseId=${course.courseId}&classId=${course.classId}` },
    { label: 'cloud-getRecs', url: '/apis/cloud/getRecs.jspx' },
    { label: 'cloud-folderHierarchy', url: '/apis/cloud/getFolderHierarchy.jspx' },
  ];
  const references: string[] = ['https://mooc1-api.chaoxing.com', 'https://mooc1-api.chaoxing.com',
    'https://mobilelearn.chaoxing.com', 'https://mobilelearn.chaoxing.com',
    'https://resource.chaoxing.com', 'https://resource.chaoxing.com'];
  for (let index: number = 0; index < routes.length; index++) {
    for (const origin of mirrors.concat([references[index]])) {
      result.push({ label: routes[index].label, url: origin + routes[index].url });
    }
  }
  result.push({ label: 'ucas-course-entry', url: mirrors[0] +
    `/mooc-ans/visit/stucoursemiddle?courseid=${course.courseId}&clazzid=${course.classId}&vc=1&cpi=${course.cpi}&ismooc2=1&v=2` });
  result.push({ label: 'reference-course-entry', url: 'https://mooc1.chaoxing.com' +
    `/mooc-ans/visit/stucoursemiddle?courseid=${course.courseId}&clazzid=${course.classId}&vc=1&cpi=${course.cpi}&ismooc2=1&v=2` });
  result.push({ label: 'server-hosts', url: mirrors[0] + '/mooc-ans/js/ServerHost.js' });
  return result;
}

export async function probeResourceEndpoints(filesDir: string,
  onResult: (probe: EndpointProbe) => void): Promise<void> {
  const catalog = await fetchCourseCatalog();
  if (catalog.courses.length === 0) throw new Error('没有可用于资源自检的课程');
  const course: Course = catalog.courses[0];
  const directory: string = filesDir + '/m3-latest';
  if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
  const evidence: ProbeEvidence[] = [];
  const candidates: ProbeTarget[] = targets(course);
  const run = async (target: ProbeTarget, index: number): Promise<void> => {
    let status: number = 0;
    let contentType: string = '';
    let finalUrl: string = '';
    let body: string = '';
    let errorKind: string = '';
    let note: string = '';
    try {
      const response: HttpResult = await send({ url: target.url });
      status = response.status;
      contentType = response.contentType;
      finalUrl = response.finalUrl;
      body = response.body;
    } catch (error) {
      const err: ApiError = error as ApiError;
      status = err.status ?? 0;
      contentType = err.contentType ?? '';
      body = err.responseBody ?? '';
      errorKind = err.kind ?? 'unknown';
      note = `${err.message} ${err.detail}`;
    }
    const id: string = (index + 1).toString().padStart(2, '0');
    const filename: string = `${id}-${target.label}.txt`;
    const bytes: number = writeText(directory + '/' + filename, body);
    const record: ProbeEvidence = { id: id, label: target.label, url: target.url, status: status,
      contentType: contentType, finalUrl: finalUrl, errorKind: errorKind, note: note,
      bytes: bytes, bodyFile: filename, preview: body.substring(0, 300) };
    evidence.push(record);
    evidence.sort((left: ProbeEvidence, right: ProbeEvidence) => left.id.localeCompare(right.id));
    writeText(directory + '/manifest.json', JSON.stringify(evidence, null, 2));
    onResult({ url: target.url, ok: status >= 200 && status < 300, status: status,
      contentType: contentType, recognized: false, preview: record.preview,
      note: `${id} ${target.label} · ${bytes} 字节 · ${filename}\n${note}` });
  };
  for (let offset: number = 0; offset < candidates.length; offset += 3) {
    const tasks: Promise<void>[] = [];
    for (let index: number = offset; index < Math.min(offset + 3, candidates.length); index++) {
      tasks.push(run(candidates[index], index));
    }
    await Promise.all(tasks);
  }
}
