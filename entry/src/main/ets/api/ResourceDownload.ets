import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { CourseResource } from '../data/ResourceModels';
import { resolveUrl } from '../common/UrlUtil';
import { SessionManager } from '../auth/SessionManager';
import { transferFile, TransferResult } from './FileTransfer';
import { send } from './HttpClient';
import { cachedResource, resourceCachePath, commitResourceCache } from './ResourceCache';
import { downloadMetadata } from './DownloadMetadata';

interface ObjectStatus { status?: string; objectid?: string; download?: string; }

export interface DownloadResult extends TransferResult { cached: boolean; }

export async function downloadResource(item: CourseResource, filesDir: string,
  onBytes: (bytes: number, total?: number) => void): Promise<DownloadResult> {
  const cached = cachedResource(item, filesDir);
  if (cached) return { path: cached.path, bytes: cached.bytes, hops: [], cached: true };
  if (!SessionManager.get().loggedIn) throw new Error('请先登录');
  let downloadUrl: string = item.downloadUrl ?? '';
  if (!downloadUrl && item.objectId) {
    const response = await send({ url: 'https://mooc.mooc.ucas.edu.cn/ananas/status/' + encodeURIComponent(item.objectId) });
    const metadata: ObjectStatus = JSON.parse(response.body) as ObjectStatus;
    if (metadata.status !== 'success' || metadata.objectid !== item.objectId || !metadata.download) throw new Error('附件未提供可用下载地址');
    downloadUrl = metadata.download;
  }
  if (!downloadUrl) throw new Error('此文件未提供下载地址，或教师未开放下载');
  const path: string = resourceCachePath(item, filesDir);
  const temporary: string = path + '.part';
  try {
    const target: string = resolveUrl('https://mooc.mooc.ucas.edu.cn', downloadUrl);
    const metadata = await downloadMetadata(target);
    const metadataFile: fs.File = fs.openSync(path + '.metadata.json', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.writeSync(metadataFile.fd, JSON.stringify(metadata)); } finally { fs.closeSync(metadataFile); }
    onBytes(0, metadata.total);
    const result: TransferResult = await transferFile(target, temporary, (bytes: number) => { onBytes(bytes, metadata.total); });
    const last = result.hops[result.hops.length - 1];
    const file: fs.File = fs.openSync(temporary, fs.OpenMode.READ_ONLY);
    const prefix: ArrayBuffer = new ArrayBuffer(Math.min(512, result.bytes));
    try { fs.readSync(file.fd, prefix); } finally { fs.closeSync(file); }
    const text: string = util.TextDecoder.create('utf-8', { fatal: false }).decodeToString(new Uint8Array(prefix)).trim().toLowerCase();
    if (result.bytes === 0 || last.contentType.includes('text/html') || /^<!doctype html|^<html/.test(text)) {
      throw new Error('服务端返回了网页或空响应，没有取得文件');
    }
    if (item.type.toLowerCase().replace('.', '') === 'pdf' && !text.startsWith('%pdf-')) throw new Error('响应不是有效的 PDF 文件');
    fs.renameSync(temporary, path);
    const completed: DownloadResult = { hops: result.hops, bytes: result.bytes, path: path, cached: false };
    const receipt: fs.File = fs.openSync(path + '.receipt.json', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.writeSync(receipt.fd, JSON.stringify(completed, null, 2)); } finally { fs.closeSync(receipt); }
    commitResourceCache(item, filesDir, result.bytes);
    return completed;
  } catch (error) {
    if (fs.accessSync(temporary)) fs.unlinkSync(temporary);
    throw error as Error;
  }
}
