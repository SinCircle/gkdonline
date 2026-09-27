import { rcp } from '@kit.RemoteCommunicationKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SessionManager } from '../auth/SessionManager';
import { hostOf, resolveUrl } from '../common/UrlUtil';
import { isLoginRedirect } from './RedirectRules';
import { ApiError, ApiErrorKind } from './errors';

export interface TransferHop {
  url: string;
  status: number;
  contentType: string;
  contentLength: string;
  contentEncoding: string;
  contentRange: string;
  location: string;
  bytes: number;
  maxChunkBytes: number;
}
export interface TransferResult { hops: TransferHop[]; bytes: number; path: string; }

function header(headers: rcp.ResponseHeaders, name: string): string {
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === name) {
      const value = headers[key];
      return typeof value === 'string' ? value : value?.join(', ') ?? '';
    }
  }
  return '';
}

/** Native chunk callback writes every buffer immediately; response bodies never accumulate in RAM. */
export async function transferFile(url: string, path: string,
  onBytes: (bytes: number) => void = () => {},
  onHop: (hop: TransferHop) => void = () => {}, maxBytes: number = Number.MAX_SAFE_INTEGER,
  range: string = ''): Promise<TransferResult> {
  let current: string = url;
  const hops: TransferHop[] = [];
  const session: rcp.Session = rcp.createSession();
  try {
    for (let index: number = 0; index <= 8; index++) {
      if (!/^https?:\/\//.test(current)) throw new Error('下载地址协议无效');
      const headers: rcp.RequestHeaders = { 'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 gkdOnline/1.0',
        'Accept': '*/*', 'Accept-Encoding': 'identity' };
      const cookie: string = SessionManager.get().cookieHeaderFor(hostOf(current));
      if (cookie.length > 0) headers['Cookie'] = cookie;
      if (range.length > 0) headers['Range'] = range;
      const request: rcp.Request = new rcp.Request(current, 'GET', headers);
      request.configuration = { transfer: { autoRedirect: false,
        timeout: { connectMs: 15000, transferMs: 3600000, inactivityMs: 30000 } } };
      const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      let bytes: number = 0;
      let maxChunkBytes: number = 0;
      request.destination = (chunk: ArrayBuffer): void => {
        maxChunkBytes = Math.max(maxChunkBytes, chunk.byteLength);
        if (bytes + chunk.byteLength > maxBytes) throw new Error('探测正文超过限定字节数');
        let offset: number = 0;
        while (offset < chunk.byteLength) {
          const buffer: ArrayBuffer = offset === 0 ? chunk : chunk.slice(offset);
          const count: number = fs.writeSync(file.fd, buffer);
          if (count <= 0) throw new Error('文件写入中断');
          offset += count;
          bytes += count;
        }
        onBytes(bytes);
      };
      let response: rcp.Response;
      try { response = await session.fetch(request); } finally { fs.closeSync(file); }
      const hop: TransferHop = { url: current, status: response.statusCode,
        contentType: header(response.headers, 'content-type'), contentLength: header(response.headers, 'content-length'),
        contentEncoding: header(response.headers, 'content-encoding'), contentRange: header(response.headers, 'content-range'),
        location: header(response.headers, 'location'), bytes: bytes, maxChunkBytes: maxChunkBytes };
      hops.push(hop);
      onHop(hop);
      if (hop.status >= 300 && hop.status < 400) {
        if (hop.location.length === 0) throw new Error('跳转响应缺少 Location');
        current = resolveUrl(current, hop.location);
        if (isLoginRedirect(current)) throw ApiError.sessionExpired('文件地址跳转到登录页');
        continue;
      }
      if (hop.status !== 200 && !(range.length > 0 && hop.status === 206)) throw new ApiError(ApiErrorKind.HTTP_STATUS, `请求失败：HTTP ${hop.status}`, hop.status);
      if (hop.contentEncoding.length === 0 && /^\d+$/.test(hop.contentLength) && Number(hop.contentLength) !== bytes) {
        throw new Error(`文件不完整：应为 ${hop.contentLength} 字节，实际 ${bytes} 字节`);
      }
      if (fs.statSync(path).size !== bytes) throw new Error('写入后的文件长度不匹配');
      return { hops: hops, bytes: bytes, path: path };
    }
    throw new Error('下载跳转超过 8 次');
  } finally { session.close(); }
}
