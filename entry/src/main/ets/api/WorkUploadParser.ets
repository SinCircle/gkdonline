import { util } from '@kit.ArkTS';
import { parseHtml, findNodes, HtmlNode, cleanText } from './WorkHtml';
import { QuestionAttachment, WorkUploadPlan } from '../data/WorkDetailModels';
import { formatAttachmentSize } from '../common/FormatSize';


interface UploadResponse { state: string; url: string; original: string; fileType: string; size: number | string; }
interface AttachmentEnvelope { objectid: string; name: string; type: string; size: string; }

export function parseWorkUploadPlan(html: string): WorkUploadPlan | undefined {
  const root: HtmlNode = parseHtml(html);
  const title: string = cleanText(findNodes(root, (n: HtmlNode) => n.tag === 'title')[0] ?? new HtmlNode());
  if (title !== '作业作答') return undefined;
  const value = (id: string): string => findNodes(root, (n: HtmlNode) => n.tag === 'input' && n.attrs['id'] === id)[0]?.attrs['value'] ?? '';
  const enc: string = value('uploadEnc');
  const timestamp: string = value('uploadTimeStamp');
  const uid: string = value('userId');
  const fileUrl: string = /UEDITOR_CONFIG\.fileUrl\s*=\s*ServerHost\.uploadDomain\s*\+\s*["']([^"']+)["']/.exec(html)?.[1] ?? '';
  if (fileUrl !== '/ueditorupload/attachment?uploadtype=work' || value('uploadtype') !== 'work' || !/^[a-f\d]{32}$/i.test(enc) || !/^\d{13}$/.test(timestamp) || !/^\d+$/.test(uid)) return undefined;
  // attachmentNew.js reads these exact hidden fields. ServerHost.js names the school upload-ans host.
  return { url: 'https://mooc.mooc.ucas.edu.cn/upload-ans' + fileUrl + '&source=1&enc2=' + enc + '&t=' + timestamp + '&uid=' + uid,
    maxBytes: 500 * 1024 * 1024 };
}

export function parseWorkUploadResponse(body: string, expectedName: string, expectedBytes: number): QuestionAttachment {
  let response: UploadResponse;
  try { response = JSON.parse(body) as UploadResponse; } catch (_) { throw new Error('上传响应不是可识别的 JSON，结果尚不确定，请勿自动重试'); }
  if (response.state !== 'SUCCESS') throw new Error('上传被拒绝：' + (response.state || '服务端未给出原因'));
  const id: string = /[?&]objectId=([a-f\d]{32})(?:&|$)/i.exec(response.url ?? '')?.[1] ?? '';
  if (!id || response.original !== expectedName || Number(response.size) !== expectedBytes || !/^\.?[a-z\d]+$/i.test(response.fileType ?? '')) {
    throw new Error('上传成功响应中的文件标识、名称、类型或字节数不匹配；请核实，勿重复上传');
  }
  return { objectId: id, name: response.original, type: response.fileType.replace(/^\./, '').toLowerCase(), size: formatAttachmentSize(expectedBytes) };
}
function escapeAttribute(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/'/g, '&#39;');
}
// Same inert attachment envelope as uploadCommon.js; all files are attached as files, not executed or inlined.
export function attachmentAnswerHtml(file: QuestionAttachment): string {
  if (!/^[a-f\d]{32}$/i.test(file.objectId) || !file.name || !/^[a-z\d]+$/i.test(file.type)) throw new Error('附件草稿字段无效');
  const envelope: AttachmentEnvelope = { objectid: file.objectId, name: file.name, type: file.type, size: file.size ?? '' };
  const encoded: string = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(encodeURIComponent(JSON.stringify(envelope))));
  return '<p><br></p><div class="editor-iframe" contenteditable="false"><iframe frameborder="0" scrolling="no" src="/ananas/common-modules/attachment/insertCloud.html" class="attach-iframe" module="insertAttach" objectid="' + file.objectId +
    '" filename="' + escapeAttribute(file.name) + '" filetype="' + escapeAttribute(file.type) + '" filesize="' + escapeAttribute(file.size ?? '') + '" name="' + encoded +
    '" style="display: block; max-width: 620px; width: 100%; height: 74px;"></iframe></div><p><br></p>';
}
