import { describe, it, expect } from '@ohos/hypium';
import { hostOf, resolveUrl } from '../main/ets/common/UrlUtil';

export default function urlUtilTest() {
  describe('UrlUtil', () => {
    it('resolves relative Location against the base directory', 0, () => {
      expect(resolveUrl('https://mooc.mooc.ucas.edu.cn/mycourse/list?term=1',
        'visit/interaction')).assertEqual('https://mooc.mooc.ucas.edu.cn/mycourse/visit/interaction');
      expect(resolveUrl('https://mooc.mooc.ucas.edu.cn',
        'visit/interaction')).assertEqual('https://mooc.mooc.ucas.edu.cn/visit/interaction');
    });
    it('keeps absolute and root-relative Location behavior', 0, () => {
      expect(resolveUrl('https://mooc.mooc.ucas.edu.cn/mycourse/list',
        '/visit/interaction')).assertEqual('https://mooc.mooc.ucas.edu.cn/visit/interaction');
      expect(resolveUrl('https://mooc.mooc.ucas.edu.cn/mycourse/list',
        'https://passport2.chaoxing.com/login')).assertEqual('https://passport2.chaoxing.com/login');
    });
    it('resolves legal URL reference forms', 0, () => {
      const base: string = 'https://a.example/x/y';
      expect(resolveUrl(base, '//b.example/z')).assertEqual('https://b.example/z');
      expect(resolveUrl(base, '?p=1')).assertEqual('https://a.example/x/y?p=1');
      expect(resolveUrl(base, '../z')).assertEqual('https://a.example/z');
      expect(resolveUrl(base, 'HTTPS://ABS/PATH')).assertEqual('https://abs/PATH');
    });
    it('keeps IPv6 literal host intact', 0, () => {
      expect(hostOf('http://[::1]:8080/x')).assertContain('::1');
    });
  });
}
