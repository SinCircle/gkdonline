import { rcp } from '@kit.RemoteCommunicationKit';
import { SessionManager } from '../auth/SessionManager';
import { hostOf, resolveUrl } from '../common/UrlUtil';
import { isLoginRedirect } from './RedirectRules';

interface MetadataHop { url: string; method: string; status: number; contentType: string; contentLength: string; location: string; }
export interface DownloadMetadata { total?: number; finalUrl: string; status: number; contentLength: string; hops: MetadataHop[]; }
function header(headers: rcp.ResponseHeaders, name: string): string {
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === name) { const value = headers[key]; return typeof value === 'string' ? value : value?.join(', ') ?? ''; }
  }
  return '';
}
// FileTransfer stays unchanged. The school rejects HEAD or returns an HTML error page.
// A separate GET observes headers, cancels immediately and discards any in-flight body chunk.
// It never accumulates a body or writes a file. Missing/encoded sizes fall back to bytes-only UI.
export async function downloadMetadata(url: string): Promise<DownloadMetadata> {
  const session: rcp.Session = rcp.createSession();
  let current: string = url;
  const hops: MetadataHop[] = [];
  try {
    for (let hop: number = 0; hop <= 8; hop++) {
      const headers: rcp.RequestHeaders = { 'Accept-Encoding': 'identity', 'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 gkdOnline/1.0' };
      const cookie: string = SessionManager.get().cookieHeaderFor(hostOf(current));
      if (cookie) headers['Cookie'] = cookie;
      const request: rcp.Request = new rcp.Request(current, 'GET', headers);
      let status: number = 0;
      let responseHeaders: rcp.ResponseHeaders = {};
      let receivedHeaders: boolean = false;
      request.configuration = {
        transfer: { autoRedirect: false, timeout: { connectMs: 5000, transferMs: 10000 } },
        tracing: { httpEventsHandler: {
          onStatusCodeReceive: (code: number) => { status = code; },
          onHeaderReceive: (value: rcp.ResponseHeaders) => {
            responseHeaders = value; receivedHeaders = true;
            if (status >= 200) session.cancel(request);
          }
        } }
      };
      request.destination = (_chunk: ArrayBuffer): void => {
        // The cancellation and native callback can race; never accumulate response data.
        session.cancel(request);
        throw new Error('元数据已读取，停止接收正文');
      };
      try {
        const response: rcp.Response = await session.fetch(request);
        status = response.statusCode; responseHeaders = response.headers; receivedHeaders = true;
      } catch (_) { if (!receivedHeaders || status < 200) break; }
      hops.push({ url: current, method: 'GET headers only', status: status,
        contentType: header(responseHeaders, 'content-type'), contentLength: header(responseHeaders, 'content-length'), location: header(responseHeaders, 'location') });
      if (status >= 300 && status < 400) {
        const location: string = header(responseHeaders, 'location');
        if (!location) break;
        current = resolveUrl(current, location);
        if (!/^https?:\/\//.test(current) || isLoginRedirect(current)) break;
        continue;
      }
      const length: string = header(responseHeaders, 'content-length');
      const encoding: string = header(responseHeaders, 'content-encoding');
      const contentType: string = header(responseHeaders, 'content-type').toLowerCase();
      const total: number | undefined = status === 200 && !contentType.includes('text/html') && !/\/(500|404|403)\.html/.test(current) && (!encoding || encoding === 'identity') && /^\d+$/.test(length) && Number(length) > 0 ? Number(length) : undefined;
      return { total: total, finalUrl: current, status: status, contentLength: length, hops: hops };
    }
  } catch (_) { /* Metadata failure does not break the verified file download path. */ }
  finally { session.close(); }
  return { finalUrl: current, status: 0, contentLength: '', hops: hops };
}
