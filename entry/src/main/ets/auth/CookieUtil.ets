/**
 * Cookie 的解析、判定与挑选。
 *
 * 超星的会话 Cookie 分两套域名（HANDOFF 2.2：国科大走了独立域名 mooc.mooc.ucas.edu.cn，
 * 而多数接口文档里写的是 chaoxing.com）。所以这里不把 Cookie 存成一根字符串，
 * 而是按域名分桶存放，发请求时按目标主机挑最长匹配的那一桶。
 */

export interface CookieEntry {
  /** 域名，如 `chaoxing.com` 或 `mooc.mooc.ucas.edu.cn`。 */
  domain: string;
  /** 该域名下 WebView 返回的原始 Cookie 串，形如 `a=1; b=2`。 */
  cookie: string;
  /** 取到这批 Cookie 时实际传给 WebCookieManager 的 URL。 */
  sourceUrl: string;
}

/** 已知的会话标记名：`_uid` 是通用账号的，`35014UID` 这类带 fid 前缀的是机构账号的。 */
const AUTH_COOKIE_NAMES: string[] = ['_uid', 'uf'];
const AUTH_COOKIE_PATTERN: RegExp = /^\d+uid$/;

/** 把 `a=1; b=2` 解析成键值对。名或值为空的项直接丢弃。 */
export function parseCookies(cookieHeader: string): Map<string, string> {
  const result: Map<string, string> = new Map<string, string>();
  for (const part of cookieHeader.split(';')) {
    const trimmed: string = part.trim();
    if (trimmed.length === 0) {
      continue;
    }
    const eq: number = trimmed.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const name: string = trimmed.substring(0, eq).trim();
    const value: string = trimmed.substring(eq + 1).trim();
    if (name.length === 0 || value.length === 0) {
      continue;
    }
    result.set(name, value);
  }
  return result;
}

/** 这个名字是否代表“已经登录”。 */
export function isAuthCookieName(name: string): boolean {
  const lower: string = name.toLowerCase();
  if (AUTH_COOKIE_NAMES.includes(lower)) {
    return true;
  }
  return AUTH_COOKIE_PATTERN.test(lower);
}

/** 任意一桶里出现了会话标记，就认为登录成功。 */
export function hasAuthCookie(entries: CookieEntry[]): boolean {
  for (const entry of entries) {
    for (const name of parseCookies(entry.cookie).keys()) {
      if (isAuthCookieName(name)) {
        return true;
      }
    }
  }
  return false;
}

/**
 * 挑出发往 host 的 Cookie。
 *
 * 匹配规则：域名完全相同，或 host 是它的子域。多个命中时取最长的域名
 * （`mooc.mooc.ucas.edu.cn` 优先于 `ucas.edu.cn`）。没命中返回空串。
 */
export function selectCookie(entries: CookieEntry[], host: string): string {
  const target: string = host.toLowerCase();
  let bestCookie: string = '';
  let bestDomainLength: number = -1;
  for (const entry of entries) {
    const domain: string = entry.domain.toLowerCase().replace(/^\./, '');
    if (domain.length === 0 || entry.cookie.length === 0) {
      continue;
    }
    const matched: boolean = target === domain || target.endsWith('.' + domain);
    if (matched && domain.length > bestDomainLength) {
      bestDomainLength = domain.length;
      bestCookie = entry.cookie;
    }
  }
  return bestCookie;
}
