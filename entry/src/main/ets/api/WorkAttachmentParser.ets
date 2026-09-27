import { HtmlNode, findNodes } from './WorkHtml';
import { QuestionAttachment } from '../data/WorkDetailModels';
import { CourseResource } from '../data/ResourceModels';

interface AttachmentStatus { status?: string; objectid: string; download: string; length: number; }

export function workAttachmentDownloadUrl(body: string, objectId: string): string {
  const response: AttachmentStatus = JSON.parse(body) as AttachmentStatus;
  // Newly uploaded TXT has no status field; confirmed raw response still supplies
  // objectid, download and length. An explicit failure is never accepted.
  if (!response || (response.status !== undefined && response.status !== 'success') ||
    response.objectid !== objectId || !(response.length > 0) || typeof response.download !== 'string') {
    throw new Error('作业附件状态未提供可校验的下载地址');
  }
  const match: RegExpExecArray | null = /^https?:\/\/cs\.mooc\.ucas\.edu\.cn\/download\/([a-f\d]{32})\?/i.exec(response.download);
  if (!match || match[1] !== objectId) throw new Error('作业附件下载地址与文件标识不一致');
  return response.download;
}

export function parseWorkAttachments(node: HtmlNode): QuestionAttachment[] {
  const files: QuestionAttachment[] = [];
  for (const iframe of findNodes(node, (n: HtmlNode) => n.tag === 'iframe')) {
    if (iframe.attrs['module'] !== 'insertAttach') continue;
    const objectId: string = iframe.attrs['objectid'] ?? '';
    const name: string = iframe.attrs['filename'] ?? '';
    if (!/^[a-f\d]{32}$/i.test(objectId) || !name) throw new Error('作业附件标识或名称无效');
    if (!files.some((f: QuestionAttachment) => f.objectId === objectId)) {
      files.push({ objectId: objectId, name: name, type: iframe.attrs['filetype'] ?? '', size: iframe.attrs['filesize'] ?? '' });
    }
  }
  return files;
}

export function workAttachmentResource(file: QuestionAttachment): CourseResource {
  if (!/^[a-f\d]{32}$/i.test(file.objectId) || !file.name) throw new Error('作业附件标识或名称无效');
  // Same object shares its cache between the stem, submitted answer and local draft.
  // The namespace cannot collide with course numeric IDs or chapter cardId:objectId IDs.
  return { id: 'work-attachment:' + file.objectId, objectId: file.objectId, name: file.name,
    type: file.type, size: file.size ?? '', creator: '', date: '', folder: false };
}
