import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { describe, it, expect } from '@ohos/hypium';
import { SessionSnapshot, SessionStore } from '../../../main/ets/auth/SessionStore';

async function aliasExists(alias: string): Promise<boolean> {
  const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(alias));
  try {
    return (await asset.query(query)).length > 0;
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    if (err.code === asset.ErrorCode.NOT_FOUND) return false;
    throw new Error(`Asset Store 测试查询失败 (${err.code})`);
  }
}

async function putTestAsset(alias: string, value: string): Promise<void> {
  const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  attributes.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(alias));
  attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(value));
  attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
  await asset.add(attributes);
}

export default function sessionStoreTest() {
  describe('SessionStore byte chunks', () => {
    it('round trips a cookie over 1387 bytes through Asset Store', 0, async () => {
      let cookie: string = 'sid=';
      // JSON 的 `{"cookie":"sid=` 前缀占 15 字节，汉字从第 799 字节开始，跨过 800 字节分片边界。
      for (let index: number = 0; index < 784; index++) cookie += 'a';
      cookie += '汉';
      for (let index: number = 0; index < 600; index++) cookie += 'b';
      const original: Uint8Array = new util.TextEncoder().encodeInto(cookie);
      const payload: Uint8Array = new util.TextEncoder().encodeInto(JSON.stringify({ cookie: cookie,
        sourceUrl: 'https://i.mooc.ucas.edu.cn/space/' }));
      expect(payload[799]).assertEqual(0xe6);
      expect(payload[800]).assertEqual(0xb1);
      expect(payload[801]).assertEqual(0x89);
      const previous: SessionSnapshot | undefined = await SessionStore.load();
      let restored: boolean = false;
      try {
        await SessionStore.save({
          cookies: [{ domain: 'i.mooc.ucas.edu.cn', cookie: cookie,
            sourceUrl: 'https://i.mooc.ucas.edu.cn/space/' }],
          loginOrigin: 'https://i.mooc.ucas.edu.cn',
          savedAt: 1,
        });
        const loaded: SessionSnapshot | undefined = await SessionStore.load();
        const result: string = loaded === undefined || loaded.cookies.length !== 1 ? '' : loaded.cookies[0].cookie;
        const actual: Uint8Array = new util.TextEncoder().encodeInto(result);
        let equal: boolean = original.length === actual.length;
        if (equal) {
          for (let index: number = 0; index < original.length; index++) {
            if (original[index] !== actual[index]) {
              equal = false;
              break;
            }
          }
        }
        hilog.info(0x0a01, 'SessionStoreTest',
          'Asset Store roundtrip inputBytes=%{public}d outputBytes=%{public}d equal=%{public}s',
          original.length, actual.length, String(equal));
        expect(original.length >= 1387).assertEqual(true);
        expect(equal).assertEqual(true);
        const prefix: string = 'gkdOnline.session.cookie.i.mooc.ucas.edu.cn#';
        expect(await aliasExists(prefix + '0')).assertEqual(true);
        expect(await aliasExists(prefix + '1')).assertEqual(true);
        await SessionStore.clear();
        const cleared: boolean = !(await aliasExists(prefix + '0')) && !(await aliasExists(prefix + '1'));
        hilog.info(0x0a01, 'SessionStoreTest', 'Asset Store clear removed both chunks=%{public}s',
          String(cleared));
        expect(cleared).assertEqual(true);
      } finally {
        if (previous === undefined) {
          await SessionStore.clear();
        } else {
          await SessionStore.save(previous);
        }
        restored = true;
      }
      expect(restored).assertEqual(true);
    });
    it('reads legacy metadata and ignores damaged metadata', 0, async () => {
      const previous: SessionSnapshot | undefined = await SessionStore.load();
      const metaAlias: string = 'gkdOnline.session.meta';
      const cookieAlias: string = 'gkdOnline.session.cookie.i.mooc.ucas.edu.cn';
      try {
        await SessionStore.clear();
        await putTestAsset(metaAlias, JSON.stringify({ loginOrigin: 'https://i.mooc.ucas.edu.cn',
          savedAt: 2, domains: ['i.mooc.ucas.edu.cn'] }));
        await putTestAsset(cookieAlias, JSON.stringify({ cookie: 'legacy=1',
          sourceUrl: 'https://i.mooc.ucas.edu.cn/space/' }));
        const legacy: SessionSnapshot | undefined = await SessionStore.load();
        expect(legacy !== undefined && legacy.cookies.length === 1 &&
          legacy.cookies[0].cookie === 'legacy=1').assertEqual(true);
        await SessionStore.clear();
        expect(await aliasExists(cookieAlias)).assertEqual(false);
        await putTestAsset(metaAlias, '{damaged');
        expect((await SessionStore.load()) === undefined).assertEqual(true);
        await SessionStore.clear();
        expect(await aliasExists(metaAlias)).assertEqual(false);
        await putTestAsset(metaAlias, 'null');
        expect((await SessionStore.load()) === undefined).assertEqual(true);
        await SessionStore.clear();
      } finally {
        if (previous === undefined) {
          await SessionStore.clear();
        } else {
          await SessionStore.save(previous);
        }
      }
    });
  });
}
