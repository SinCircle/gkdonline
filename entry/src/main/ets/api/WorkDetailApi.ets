import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkDetail } from '../data/WorkDetailModels';
import { SessionManager } from '../auth/SessionManager';
import { ApiError, ApiErrorKind } from './errors';
import { transferFile } from './FileTransfer';
import { parseWorkDetail } from './WorkDetailParser';
import { parseWorkModifyUrl } from './WorkFormParser';
import { cleanText, parseHtml } from './WorkHtml';
import { resolveUrl, hostOf } from '../common/UrlUtil';

export interface WorkDetailPage { detail: WorkDetail; modifyUrl: string; }

export async function fetchWorkDetailPage(url: string, cacheDir: string): Promise<WorkDetailPage> {
  if (!SessionManager.get().loggedIn) throw ApiError.sessionExpired('请先登录');
  const target: string = resolveUrl('https://mooc.mooc.ucas.edu.cn', url);
  if (hostOf(target) !== 'mooc.mooc.ucas.edu.cn' || !/^https:\/\//.test(target)) throw new ApiError(ApiErrorKind.PARSE, '作业详情地址不受支持');
  const path: string = cacheDir + '/detail-' + Date.now().toString() + '-' + Math.random().toString(36).substring(2) + '.html';
  try {
    // GET HTML only. Native transport never evaluates scripts, iframes or form actions.
    await transferFile(target, path, () => {}, () => {}, 8 * 1024 * 1024);
    const html: string = fs.readTextSync(path);
    let detail: WorkDetail;
    try { detail = parseWorkDetail(html); }
    catch (error) {
      const title: string = /<title[^>]*>([^<]*)<\/title>/i.exec(html)?.[1].trim() ?? '';
      const page: string = title || '无标题';
      const form: string = /id=["']submitForm["']/i.test(html) ? '有提交表单' : '无提交表单';
      const note: string = cleanText(parseHtml(html)).replace(/^提示\s*/, '').trim().substring(0, 180);
      if (title === '提示' && !/id=["']submitForm["']/i.test(html) && note) {
        throw new ApiError(ApiErrorKind.PARSE, note);
      }
      throw new ApiError(ApiErrorKind.PARSE, `未识别作业页面（${page}，${form}）：${(error as Error).message}`);
    }
    return { detail: detail, modifyUrl: parseWorkModifyUrl(html) };
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(ApiErrorKind.NETWORK, (error as Error).message);
  } finally { if (fs.accessSync(path)) fs.unlinkSync(path); }
}

export async function fetchWorkDetail(url: string, cacheDir: string): Promise<WorkDetail> {
  return (await fetchWorkDetailPage(url, cacheDir)).detail;
}
