/** 分域 Cookie 与小型元数据分别存入 Asset Store；单条 SECRET 不超过 1000 字节。 */
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CookieEntry } from './CookieUtil';

const DOMAIN: number = 0x0a01;
const TAG: string = 'SessionStore';
const META_ALIAS: string = 'gkdOnline.session.meta';
const COOKIE_ALIAS_PREFIX: string = 'gkdOnline.session.cookie.';
const LEGACY_ALIAS: string = 'gkdOnline.session';
const SECRET_LIMIT: number = 1000;
const COOKIE_CHUNK_SIZE: number = 800;

export interface SessionSnapshot {
  cookies: CookieEntry[];
  loginOrigin: string;
  savedAt: number;
}

interface SessionMetadata {
  loginOrigin: string;
  savedAt: number;
  domains: Array<DomainChunks | string>;
}

interface DomainChunks {
  domain: string;
  chunks: number;
}

interface StoredCookie {
  cookie: string;
  sourceUrl: string;
}

interface PreparedCookie {
  domain: string;
  secrets: Uint8Array[];
}

function encode(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function aliasAttribute(alias: string): asset.AssetMap {
  const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  attributes.set(asset.Tag.ALIAS, encode(alias));
  return attributes;
}

function prepareSecret(domain: string, payload: string): Uint8Array {
  const bytes: Uint8Array = encode(payload);
  if (bytes.length === 0 || bytes.length > SECRET_LIMIT) {
    hilog.error(DOMAIN, TAG, '域 %{public}s 的凭证为 %{public}d 字节，超出 %{public}d 字节限制',
      domain, bytes.length, SECRET_LIMIT);
    throw new Error(`域 ${domain} 的凭证为 ${bytes.length} 字节，超出 Asset Store 单条限制`);
  }
  return bytes;
}

function splitCookie(payload: string): Uint8Array[] {
  const bytes: Uint8Array = encode(payload);
  const chunks: Uint8Array[] = [];
  for (let offset: number = 0; offset < bytes.length; offset += COOKIE_CHUNK_SIZE) {
    chunks.push(bytes.slice(offset, offset + COOKIE_CHUNK_SIZE));
  }
  return chunks;
}

function parseMetadata(text: string): SessionMetadata | undefined {
  let metadata: SessionMetadata;
  try {
    metadata = JSON.parse(text) as SessionMetadata;
  } catch (error) {
    hilog.warn(DOMAIN, TAG, '会话元数据无法解析，按未登录处理');
    return undefined;
  }
  if (metadata === null || typeof metadata !== 'object' || !Array.isArray(metadata.domains) ||
    typeof metadata.loginOrigin !== 'string' ||
    typeof metadata.savedAt !== 'number') {
    hilog.warn(DOMAIN, TAG, '会话元数据格式错误，按未登录处理');
    return undefined;
  }
  for (const item of metadata.domains) {
    if (typeof item === 'string') continue;
    if (typeof item !== 'object' || item === null || typeof item.domain !== 'string' ||
      typeof item.chunks !== 'number' || !Number.isInteger(item.chunks) || item.chunks < 1 ||
      item.chunks > 4096) {
      hilog.warn(DOMAIN, TAG, '会话元数据域格式错误，按未登录处理');
      return undefined;
    }
  }
  return metadata;
}

async function put(alias: string, secret: Uint8Array): Promise<void> {
  const attributes: asset.AssetMap = aliasAttribute(alias);
  attributes.set(asset.Tag.SECRET, secret);
  attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  try {
    await asset.add(attributes);
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    const domain: string = alias.startsWith(COOKIE_ALIAS_PREFIX) ?
      alias.substring(COOKIE_ALIAS_PREFIX.length) : 'metadata';
    hilog.error(DOMAIN, TAG, '域 %{public}s 的资产写入失败，错误码 %{public}d', domain, err.code);
    throw new Error(`Asset Store 写入 ${alias} 失败 (${err.code})`);
  }
}

async function readBytes(alias: string): Promise<Uint8Array | undefined> {
  const query: asset.AssetMap = aliasAttribute(alias);
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  let found: Array<asset.AssetMap>;
  try {
    found = await asset.query(query);
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    if (err.code === asset.ErrorCode.NOT_FOUND) return undefined;
    throw new Error(`Asset Store 读取失败 (${err.code})`);
  }
  if (found.length === 0) return undefined;
  const secret: asset.Value | undefined = found[0].get(asset.Tag.SECRET);
  if (!(secret instanceof Uint8Array)) {
    throw new Error('Asset Store 的 SECRET 字段缺失');
  }
  return secret;
}

async function read(alias: string): Promise<string | undefined> {
  const secret: Uint8Array | undefined = await readBytes(alias);
  return secret === undefined ? undefined : util.TextDecoder.create('utf-8').decodeToString(secret);
}

async function remove(alias: string): Promise<void> {
  try {
    await asset.remove(aliasAttribute(alias));
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    if (err.code !== asset.ErrorCode.NOT_FOUND) {
      throw new Error(`Asset Store 删除失败 (${err.code})`);
    }
  }
}

export class SessionStore {
  /** Cookie 按字节分片；元数据最后写入，只有完整写入的快照才可见。 */
  static async save(snapshot: SessionSnapshot): Promise<void> {
    const prepared: PreparedCookie[] = [];
    const domains: DomainChunks[] = [];
    for (const entry of snapshot.cookies) {
      if (domains.some((item: DomainChunks) => item.domain === entry.domain)) {
        throw new Error(`重复的凭证域 ${entry.domain}`);
      }
      const value: StoredCookie = { cookie: entry.cookie, sourceUrl: entry.sourceUrl };
      const secrets: Uint8Array[] = splitCookie(JSON.stringify(value));
      prepared.push({ domain: entry.domain, secrets: secrets });
      domains.push({ domain: entry.domain, chunks: secrets.length });
    }
    const metadata: SessionMetadata = {
      loginOrigin: snapshot.loginOrigin,
      savedAt: snapshot.savedAt,
      domains: domains,
    };
    const metadataSecret: Uint8Array = prepareSecret('metadata', JSON.stringify(metadata));
    await SessionStore.clear();
    try {
      for (const item of prepared) {
        for (let index: number = 0; index < item.secrets.length; index++) {
          await put(`${COOKIE_ALIAS_PREFIX}${item.domain}#${index}`, item.secrets[index]);
        }
      }
      await put(META_ALIAS, metadataSecret);
    } catch (error) {
      for (const item of prepared) {
        for (let index: number = 0; index < item.secrets.length; index++) {
          try {
            await remove(`${COOKIE_ALIAS_PREFIX}${item.domain}#${index}`);
          } catch (cleanupError) {
            hilog.error(DOMAIN, TAG, '域 %{public}s 的失败资产清理失败', item.domain);
          }
        }
      }
      try { await remove(META_ALIAS); } catch (cleanupError) {
        hilog.error(DOMAIN, TAG, '失败会话的元数据清理失败');
      }
      const err: Error = error as Error;
      throw new Error(`保存 Asset Store 凭证失败: ${err.message}`);
    }
  }

  /** 单域损坏或读取失败时记日志并继续读取其余域。 */
  static async load(): Promise<SessionSnapshot | undefined> {
    const text: string | undefined = await read(META_ALIAS);
    if (text === undefined) return undefined;
    const metadata: SessionMetadata | undefined = parseMetadata(text);
    if (metadata === undefined) return undefined;
    const cookies: CookieEntry[] = [];
    for (const item of metadata.domains) {
      const domain: string = typeof item === 'string' ? item : item.domain;
      try {
        const parts: Uint8Array[] = [];
        const count: number = typeof item === 'string' ? 1 : item.chunks;
        let length: number = 0;
        for (let index: number = 0; index < count; index++) {
          const alias: string = typeof item === 'string' ? COOKIE_ALIAS_PREFIX + domain :
            `${COOKIE_ALIAS_PREFIX}${domain}#${index}`;
          const part: Uint8Array | undefined = await readBytes(alias);
          if (part === undefined) throw new Error('Cookie 分片缺失');
          parts.push(part);
          length += part.length;
        }
        const bytes: Uint8Array = new Uint8Array(length);
        let offset: number = 0;
        for (const part of parts) {
          bytes.set(part, offset);
          offset += part.length;
        }
        const raw: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
        const value: StoredCookie = JSON.parse(raw) as StoredCookie;
        if (typeof value.cookie !== 'string' || typeof value.sourceUrl !== 'string') {
          throw new Error('Cookie 资产格式错误');
        }
        cookies.push({ domain: domain, cookie: value.cookie, sourceUrl: value.sourceUrl });
      } catch (error) {
        hilog.error(DOMAIN, TAG, '域 %{public}s 的凭证读取或解析失败', domain);
      }
    }
    return { cookies: cookies, loginOrigin: metadata.loginOrigin, savedAt: metadata.savedAt };
  }

  /** 清除元数据及其中列出的分域资产。 */
  static async clear(): Promise<void> {
    await remove(LEGACY_ALIAS);
    const text: string | undefined = await read(META_ALIAS);
    if (text === undefined) return;
    const metadata: SessionMetadata | undefined = parseMetadata(text);
    if (metadata === undefined) {
      await remove(META_ALIAS);
      return;
    }
    for (const item of metadata.domains) {
      const domain: string = typeof item === 'string' ? item : item.domain;
      if (typeof item !== 'string') {
        for (let index: number = 0; index < item.chunks; index++) {
          await remove(`${COOKIE_ALIAS_PREFIX}${domain}#${index}`);
        }
      }
      await remove(COOKIE_ALIAS_PREFIX + domain);
    }
    await remove(META_ALIAS);
  }
}
