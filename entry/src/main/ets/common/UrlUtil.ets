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

/**
 * 学校镜像域名下的地址一律换成 https。
 *
 * 通知附件的入口地址在服务端渲染时写的是明文 http（实测见
 * `verification/notices-pc-20260927/intoexamorwork-probe.json`），照原样请求会落到登录页。
 * 只认 `mooc.ucas.edu.cn` 这一套域名，第三方地址原样返回、不改协议。
 */
export function toHttpsForCampus(input: string): string {
  const host: string = hostOf(input).toLowerCase();
  if (host !== 'mooc.ucas.edu.cn' && !host.endsWith('.mooc.ucas.edu.cn')) {
    return input;
  }
  return /^http:\/\//i.test(input) ? 'https://' + input.substring('http://'.length) : input;
}

/** 取查询串里某个参数的原样值（不做百分号解码，入参是服务端生成的数字 ID）。没有该参数时返回空串。 */
export function queryParam(input: string, name: string): string {
  const query: number = input.indexOf('?');
  if (query < 0) {
    return '';
  }
  const fragment: number = input.indexOf('#', query);
  const text: string = fragment < 0 ? input.substring(query + 1) : input.substring(query + 1, fragment);
  for (const part of text.split('&')) {
    const eq: number = part.indexOf('=');
    if (eq > 0 && part.substring(0, eq) === name) {
      return part.substring(eq + 1);
    }
  }
  return '';
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
