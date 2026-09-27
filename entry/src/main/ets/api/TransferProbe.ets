import { fileIo as fs } from '@kit.CoreFileKit';
import { transferFile, TransferHop } from './FileTransfer';
import { EndpointProbe } from './CourseApi';

export interface TransferTarget { label: string; url: string; range?: string; }
export interface ProbeRecord {
  id: string; label: string; url: string; status: number; contentType: string;
  bytes: number; bodyFile: string; note: string; hops: TransferHop[];
}
export function saveProbeText(path: string, text: string): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { if (text.length > 0) fs.writeSync(file.fd, text); } finally { fs.closeSync(file); }
}
export async function runTransferProbes(filesDir: string, name: string, targets: TransferTarget[],
  onResult: (result: EndpointProbe) => void): Promise<ProbeRecord[]> {
  const directory: string = filesDir + '/' + name;
  if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
  const records: ProbeRecord[] = [];
  for (let index: number = 0; index < targets.length; index++) {
    const target: TransferTarget = targets[index];
    const id: string = (index + 1).toString().padStart(2, '0');
    const filename: string = id + '-' + target.label + '.txt';
    const hops: TransferHop[] = [];
    let note: string = '';
    try { await transferFile(target.url, directory + '/' + filename, () => {}, (hop: TransferHop) => { hops.push(hop); },
      8 * 1024 * 1024, target.range ?? ''); }
    catch (error) { note = (error as Error).message; }
    const last: TransferHop | undefined = hops[hops.length - 1];
    const bytes: number = fs.accessSync(directory + '/' + filename) ? fs.statSync(directory + '/' + filename).size : 0;
    const record: ProbeRecord = { id: id, label: target.label, url: target.url, status: last?.status ?? 0,
      contentType: last?.contentType ?? '', bytes: bytes, bodyFile: filename, note: note, hops: hops };
    records.push(record);
    saveProbeText(directory + '/manifest.json', JSON.stringify(records, null, 2));
    let preview: string = '';
    if (bytes > 0 && record.contentType.match(/text|json|javascript/)) preview = fs.readTextSync(directory + '/' + filename).substring(0, 300);
    onResult({ url: target.url, ok: note.length === 0, status: record.status, contentType: record.contentType,
      recognized: false, preview: preview, note: `${id} ${target.label} · ${bytes} 字节 · ${note}\n` +
        hops.map((hop: TransferHop) => `${hop.status} Content-Length=${hop.contentLength} → ${hop.location}`).join('\n') });
  }
  return records;
}
