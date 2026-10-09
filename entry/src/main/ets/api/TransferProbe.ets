import { fileIo as fs } from '@kit.CoreFileKit';

/** 把文本写进应用沙箱。作业答案草稿（`*.draft.json`）和提交回执都走这里。 */
export function saveProbeText(path: string, text: string): void {
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { if (text.length > 0) fs.writeSync(file.fd, text); } finally { fs.closeSync(file); }
}
