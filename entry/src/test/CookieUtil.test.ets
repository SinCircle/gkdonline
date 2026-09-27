import { describe, it, expect } from '@ohos/hypium';
import { CookieEntry, parseCookies, isAuthCookieName, hasAuthCookie, selectCookie } from '../main/ets/auth/CookieUtil';

export default function cookieUtilTest() {
  describe('CookieUtil', () => {
    it('parses names and values and ignores malformed items', 0, () => {
      const parsed: Map<string, string> = parseCookies(' a=1; b=hello=world; empty=; =bad; broken');
      expect(parsed.size).assertEqual(2);
      expect(parsed.get('a')).assertEqual('1');
      expect(parsed.get('b')).assertEqual('hello=world');
    });
    it('recognizes session markers', 0, () => {
      expect(isAuthCookieName('_uid')).assertTrue();
      expect(isAuthCookieName('uf')).assertTrue();
      expect(isAuthCookieName('35014UID')).assertTrue();
      expect(isAuthCookieName('UID')).assertFalse();
      expect(isAuthCookieName('fid')).assertFalse();
      expect(hasAuthCookie([{ domain: 'ucas.edu.cn', cookie: 'fid=35014; 35014UID=123',
        sourceUrl: 'https://ucas.edu.cn/' }])).assertTrue();
      expect(hasAuthCookie([{ domain: 'chaoxing.com', cookie: 'fid=35014',
        sourceUrl: 'https://chaoxing.com/' }])).assertFalse();
    });
    it('chooses the longest matching domain', 0, () => {
      const entries: CookieEntry[] = [
        { domain: 'ucas.edu.cn', cookie: 'wide=1', sourceUrl: 'https://ucas.edu.cn/' },
        { domain: 'mooc.ucas.edu.cn', cookie: 'near=1', sourceUrl: 'https://mooc.ucas.edu.cn/' },
        { domain: 'mooc.mooc.ucas.edu.cn', cookie: 'exact=1',
          sourceUrl: 'https://mooc.mooc.ucas.edu.cn/' },
      ];
      expect(selectCookie(entries, 'mooc.mooc.ucas.edu.cn')).assertEqual('exact=1');
      expect(selectCookie(entries, 'a.mooc.ucas.edu.cn')).assertEqual('near=1');
      expect(selectCookie(entries, 'notucas.edu.cn')).assertEqual('');
    });
    it('handles empty input', 0, () => {
      expect(parseCookies('').size).assertEqual(0);
      expect(hasAuthCookie([])).assertFalse();
      expect(selectCookie([], 'mooc.ucas.edu.cn')).assertEqual('');
      expect(selectCookie([{ domain: '', cookie: 'a=1', sourceUrl: '' }], 'a')).assertEqual('');
    });
  });
}
