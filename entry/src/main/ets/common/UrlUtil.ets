/**
 * URL 拆解工具。
 *
 * Location 的相对引用与 IPv6 主机交给系统 URL 解析器处理。
 */
import { url } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0a01;
const TAG: string = 'UrlUtil';

/** 取出主机名，去掉协议、用户信息、端口、路径、查询串。解析不出来时返回空串。 */
export function hostOf(input: string): string {
  try {
    return url.URL.parseURL(input).hostname;
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    hilog.warn(DOMAIN, TAG, '主机解析失败，错误码 %{public}d', err.code);
    return '';
  }
}

/** 取出 `协议://主机[:端口]`。解析不出来时返回空串。 */
export function originOf(url: string): string {
  const schemeEnd: number = url.indexOf('://');
  if (schemeEnd < 0) {
    return '';
  }
  const start: number = schemeEnd + 3;
  let end: number = url.length;
  const slash: number = url.indexOf('/', start);
  const query: number = url.indexOf('?', start);
  const fragment: number = url.indexOf('#', start);
  if (slash >= 0 && slash < end) end = slash;
  if (query >= 0 && query < end) end = query;
  if (fragment >= 0 && fragment < end) end = fragment;
  return url.substring(0, end);
}

/** 用系统解析器把合法 Location 解析为绝对地址。 */
export function resolveUrl(base: string, location: string): string {
  try {
    return url.URL.parseURL(location, base).toString();
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    hilog.warn(DOMAIN, TAG, 'Location 解析失败，错误码 %{public}d', err.code);
    return location.indexOf('://') >= 0 ? location : '';
  }
}
