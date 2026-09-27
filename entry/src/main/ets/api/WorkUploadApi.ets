import { http } from '@kit.NetworkKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { parseWorkUploadResponse } from './WorkUploadParser';
import { QuestionAttachment, WorkUploadPlan } from '../data/WorkDetailModels';
import { SessionManager } from '../auth/SessionManager';
import { safeFileName } from './ResourceCache';
import { saveProbeText } from './TransferProbe';

export interface SelectedWorkFile { path: string; name: string; bytes: number; mime: string; modified: string; }
export interface UploadField { name: string; value: string; }
interface UploadReceipt { time: string; url: string; fields: UploadField[]; fileName: string; fileBytes: number; status: number; contentType: string; body: string; phase: string; }

export async function copySelectedWorkFile(uri: string, cacheDir: string): Promise<SelectedWorkFile> {
  const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  const name: string = new fileUri.FileUri(uri).name;
  const path: string = cacheDir + '/work-upload-' + Date.now().toString() + '-' + safeFileName(name);
  try {
    const stat: fs.Stat = fs.statSync(file.fd);
    if (!name || stat.size <= 0 || stat.size > 500 * 1024 * 1024) throw new Error('请选择非空且不超过 500 MB 的文件');
    await fs.copyFile(file.fd, path);
    if (fs.statSync(path).size !== stat.size) throw new Error('选中文件复制不完整');
    const ext: string = name.split('.').pop()?.toLowerCase() ?? '';
    const mime: string = ext === 'txt' ? 'text/plain' : ext === 'pdf' ? 'application/pdf' : 'application/octet-stream';
    return { path: path, name: name, bytes: stat.size, mime: mime, modified: new Date(stat.mtime * 1000).toString() };
  } catch (error) { if (fs.accessSync(path)) fs.unlinkSync(path); throw error as Error; }
  finally { fs.closeSync(file); }
}
export function discardSelectedWorkFile(file: SelectedWorkFile): void { if (fs.accessSync(file.path)) fs.unlinkSync(file.path); }
export function workUploadFields(file: SelectedWorkFile): UploadField[] {
  // WebUploader's exact metadata names, observed in webuploader.nolog.min.js.
  return [{ name: 'id', value: 'WU_FILE_0' }, { name: 'name', value: file.name }, { name: 'type', value: file.mime },
    { name: 'lastModifiedDate', value: file.modified }, { name: 'size', value: file.bytes.toString() }];
}

// Only an attachment upload. Never calls a work submission, save-answer or delete endpoint.
// Native filePath multipart avoids reading the file into a JavaScript-sized ArrayBuffer.
export async function uploadWorkAttachment(plan: WorkUploadPlan, file: SelectedWorkFile, filesDir: string,
  onProgress: (sent: number, total: number) => void): Promise<QuestionAttachment> {
  if (!SessionManager.get().loggedIn) throw new Error('请先登录');
  if (!plan.url.startsWith('https://mooc.mooc.ucas.edu.cn/upload-ans/ueditorupload/attachment?uploadtype=work&') || file.bytes > plan.maxBytes || fs.statSync(file.path).size !== file.bytes) throw new Error('上传参数或文件长度校验失败');
  const directory: string = filesDir + '/work-uploads';
  if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
  const receipt: UploadReceipt = { time: new Date().toISOString(), url: plan.url, fields: workUploadFields(file), fileName: file.name,
    fileBytes: file.bytes, status: 0, contentType: '', body: '', phase: 'pending' };
  const receiptPath: string = directory + '/' + Date.now().toString() + '.json';
  saveProbeText(receiptPath, JSON.stringify(receipt, null, 2));
  const parts: http.MultiFormData[] = receipt.fields.map((f: UploadField): http.MultiFormData => ({ name: f.name, contentType: 'text/plain', data: f.value }));
  parts.push({ name: 'upfile', contentType: file.mime, remoteFileName: file.name, filePath: file.path });
  const request: http.HttpRequest = http.createHttp();
  let lastUpdate: number = 0;
  request.on('dataSendProgress', (progress: http.DataSendProgressInfo) => {
    if (Date.now() - lastUpdate >= 250) { lastUpdate = Date.now(); onProgress(progress.sendSize, progress.totalSize); }
  });
  try {
    // One attempt; redirects and automatic retries are disabled.
    const response: http.HttpResponse = await request.request(plan.url, { method: http.RequestMethod.POST, maxRedirects: 0,
      expectDataType: http.HttpDataType.STRING, connectTimeout: 15000, readTimeout: 3600000,
      header: { 'Cookie': SessionManager.get().cookieHeaderFor('mooc.mooc.ucas.edu.cn'),
        'Content-Type': 'multipart/form-data', 'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 gkdOnline/1.0' },
      multiFormDataList: parts });
    receipt.status = response.responseCode;
    receipt.body = typeof response.result === 'string' ? response.result : '';
    const headers = response.header as Record<string, string>;
    const ct: string | undefined = Object.keys(headers).find((k: string) => k.toLowerCase() === 'content-type');
    receipt.contentType = ct ? headers[ct] : ''; receipt.phase = 'response';
    saveProbeText(receiptPath, JSON.stringify(receipt, null, 2));
    if (receipt.status !== 200) throw new Error(`上传返回 HTTP ${receipt.status}：${receipt.body.substring(0, 200)}`);
    return parseWorkUploadResponse(receipt.body, file.name, file.bytes);
  } catch (error) {
    if (receipt.phase === 'pending') { receipt.phase = 'uncertain'; receipt.body = (error as Error).message; saveProbeText(receiptPath, JSON.stringify(receipt, null, 2)); }
    throw error as Error;
  } finally { request.destroy(); }
}
