import { hostOf, originOf } from '../common/UrlUtil';

/** 只根据跳转目标的主机和路径识别登录页，避免把 ucas.edu.cn 误当成 CAS。 */
export function isLoginRedirect(url: string): boolean {
  const origin: string = originOf(url);
  if (origin.length === 0) {
    return false;
  }
  const host: string = hostOf(url).toLowerCase();
  if (host === 'passport.mooc.ucas.edu.cn' ||
    host === 'passport2.chaoxing.com' || host.endsWith('.passport2.chaoxing.com')) {
    return true;
  }

  let end: number = url.length;
  const query: number = url.indexOf('?', origin.length);
  const fragment: number = url.indexOf('#', origin.length);
  if (query >= 0 && query < end) end = query;
  if (fragment >= 0 && fragment < end) end = fragment;
  const path: string = url.substring(origin.length, end).toLowerCase();
  // 国科大还会把 passport 主机名作为 i.mooc.ucas.edu.cn 路径中的完整一段。
  if (host === 'i.mooc.ucas.edu.cn' && path.split('/').includes('passport.mooc.ucas.edu.cn')) {
    return true;
  }
  return path === '/login' || path === '/unitlogin' ||
    path === '/sso' || path.startsWith('/sso/') ||
    path === '/cas' || path.startsWith('/cas/');
}
