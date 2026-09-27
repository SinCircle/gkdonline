import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkDetail } from '../data/WorkDetailModels';
import { SessionManager } from '../auth/SessionManager';
import { ApiError, ApiErrorKind } from './errors';
import { transferFile } from './FileTransfer';
import { parseWorkDetail } from './WorkDetailParser';
import { resolveUrl, hostOf } from '../common/UrlUtil';

export async function fetchWorkDetail(url: string, cacheDir: string): Promise<WorkDetail> {
  if (!SessionManager.get().loggedIn) throw ApiError.sessionExpired('请先登录');
  const target: string = resolveUrl('https://mooc.mooc.ucas.edu.cn', url);
  if (hostOf(target) !== 'mooc.mooc.ucas.edu.cn' || !/^https:\/\//.test(target)) throw new ApiError(ApiErrorKind.PARSE, '作业详情地址不受支持');
  const path: string = cacheDir + '/detail-' + Date.now().toString() + '-' + Math.random().toString(36).substring(2) + '.html';
  try {
    // GET HTML only. Native transport never evaluates scripts, iframes or form actions.
    await transferFile(target, path, () => {}, () => {}, 8 * 1024 * 1024);
    return parseWorkDetail(fs.readTextSync(path));
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(ApiErrorKind.NETWORK, (error as Error).message);
  } finally { if (fs.accessSync(path)) fs.unlinkSync(path); }
}
