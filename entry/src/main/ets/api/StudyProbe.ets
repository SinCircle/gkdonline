/** Reuses the connection-check UI; all raw evidence stays in the app sandbox. */
import { fileIo as fs } from '@kit.CoreFileKit';
import { EndpointProbe, fetchCourseCatalog } from './CourseApi';
import { runTransferProbes } from './TransferProbe';
import { workListUrl, parseWorkList } from './WorkParser';
import { TransferResult } from './FileTransfer';

export async function probeStudy(filesDir: string, onResult: (result: EndpointProbe) => void): Promise<void> {
  const catalog = await fetchCourseCatalog();
  if (catalog.courses.length === 0) return;
  const course = catalog.courses[0];
  const directory: string = 'm4-latest-work-entry';
  const records = await runTransferProbes(filesDir, directory, [{ label: 'course-work-entry',
    url: 'https://mooc.mooc.ucas.edu.cn/mooc-ans/visit/stucoursemiddle' +
      `?courseid=${course.courseId}&clazzid=${course.classId}&vc=1&cpi=${course.cpi}&ismooc2=1&v=2` }], onResult);
  const html: string = fs.readTextSync(filesDir + '/' + directory + '/' + records[0].bodyFile);
  const url: string = workListUrl(html, course);
  const lists = await runTransferProbes(filesDir, 'm4-latest-work-list', [{ label: 'course-work-list', url: url }], onResult);
  const body: string = fs.readTextSync(filesDir + '/m4-latest-work-list/' + lists[0].bodyFile);
  const count: number = parseWorkList(body, course).length;
  onResult({ url: url, ok: true, status: 200, contentType: lists[0].contentType, recognized: true,
    preview: body.substring(0, 300), note: `已识别 ${course.name} 的作业首页：${count} 条。样本仅存本机。` });
  const downloads: string = filesDir + '/downloads';
  if (!fs.accessSync(downloads)) return;
  const receipts: string[] = fs.listFileSync(downloads).filter((name: string) => name.endsWith('.receipt.json'));
  for (const filename of receipts) {
    const receipt: TransferResult = JSON.parse(fs.readTextSync(downloads + '/' + filename)) as TransferResult;
    for (const hop of receipt.hops) {
      onResult({ url: hop.url, ok: hop.status === 200, status: hop.status, contentType: hop.contentType, recognized: false,
        preview: '', note: `${filename}\nContent-Length=${hop.contentLength}；实际写入=${hop.bytes}；最大数据块=${hop.maxChunkBytes}\nLocation=${hop.location}` });
    }
  }
}