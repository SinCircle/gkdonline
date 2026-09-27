import { fileIo as fs } from '@kit.CoreFileKit';
import { CourseResource } from '../data/ResourceModels';

export interface CachedResource { path: string; bytes: number; }
interface CacheRecord { version: number; id: string; fileName: string; bytes: number; }
interface LegacyReceipt { bytes: number; }

export function safeFileName(name: string): string {
  return name.replace(/[\\/\u0000-\u001f:*?"<>|]/g, '_').replace(/^\.+/, '_').substring(0, 180) || '下载文件';
}

function directory(id: string, filesDir: string): string {
  // encodeURIComponent preserves the identity of both numeric IDs and cardId:objectId.
  return filesDir + '/downloads/' + encodeURIComponent(id).replace(/\./g, '%2E');
}

export function resourceCachePath(item: CourseResource, filesDir: string): string {
  const parent: string = directory(item.id, filesDir) + '/content';
  if (!fs.accessSync(parent)) fs.mkdirSync(parent, true);
  return parent + '/' + safeFileName(item.name);
}

export function commitResourceCache(item: CourseResource, filesDir: string, bytes: number): void {
  const record: CacheRecord = { version: 1, id: item.id, fileName: safeFileName(item.name), bytes: bytes };
  const path: string = directory(item.id, filesDir) + '/index.json';
  const file: fs.File = fs.openSync(path + '.part', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { fs.writeSync(file.fd, JSON.stringify(record)); } finally { fs.closeSync(file); }
  fs.renameSync(path + '.part', path);
}

export function cachedResource(item: CourseResource, filesDir: string): CachedResource | undefined {
  if (item.folder || !item.id) return undefined;
  const parent: string = directory(item.id, filesDir);
  try {
    if (fs.accessSync(parent + '/index.json')) {
      const record: CacheRecord = JSON.parse(fs.readTextSync(parent + '/index.json')) as CacheRecord;
      if (record.version !== 1 || record.id !== item.id || typeof record.fileName !== 'string' ||
        record.fileName !== safeFileName(record.fileName) || !(record.bytes > 0)) return undefined;
      const path: string = parent + '/content/' + record.fileName;
      if (!fs.accessSync(path) || fs.statSync(path).size !== record.bytes) return undefined;
      return { path: path, bytes: record.bytes };
    }
    // Adopt completed downloads from the previous version; never adopt .part files.
    const old: string = filesDir + '/downloads/' + item.id.replace(/[^a-zA-Z0-9_-]/g, '_') + '-' + safeFileName(item.name);
    if (!fs.accessSync(old) || !fs.accessSync(old + '.receipt.json')) return undefined;
    const receipt: LegacyReceipt = JSON.parse(fs.readTextSync(old + '.receipt.json')) as LegacyReceipt;
    if (!(receipt.bytes > 0) || fs.statSync(old).size !== receipt.bytes) return undefined;
    const path: string = resourceCachePath(item, filesDir);
    fs.renameSync(old, path);
    fs.renameSync(old + '.receipt.json', path + '.receipt.json');
    commitResourceCache(item, filesDir, receipt.bytes);
    return { path: path, bytes: receipt.bytes };
  } catch (_) { return undefined; }
}
