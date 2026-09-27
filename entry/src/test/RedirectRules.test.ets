import { describe, it, expect } from '@ohos/hypium';
import { isLoginRedirect } from '../main/ets/api/RedirectRules';

export default function redirectRulesTest() {
  describe('RedirectRules', () => {
    it('does not confuse the UCAS host with a CAS login path', 0, () => {
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/visit/interaction')).assertFalse();
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/cascade/list')).assertFalse();
    });
    it('recognizes login destinations by host or path', 0, () => {
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/login')).assertTrue();
      expect(isLoginRedirect('https://passport2.chaoxing.com/login?loginType=3')).assertTrue();
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/unitlogin')).assertTrue();
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/sso/enter')).assertTrue();
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/cas')).assertTrue();
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/cas/enter')).assertTrue();
    });
    it('recognizes the UCAS passport host', 0, () => {
      expect(isLoginRedirect('https://passport.mooc.ucas.edu.cn/login?fid=')).assertTrue();
    });
    it('recognizes the UCAS passport host as a complete path segment', 0, () => {
      expect(isLoginRedirect('http://i.mooc.ucas.edu.cn/space/passport.mooc.ucas.edu.cn/login?fid=')).assertTrue();
    });
    it('requires host and path boundaries', 0, () => {
      expect(isLoginRedirect('https://fakepassport2.chaoxing.com/visit')).assertFalse();
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/login-help')).assertFalse();
      expect(isLoginRedirect('https://mooc.mooc.ucas.edu.cn/visit?next=/login')).assertFalse();
      expect(isLoginRedirect('https://fakepassport.mooc.ucas.edu.cn/space/')).assertFalse();
      expect(isLoginRedirect('https://i.mooc.ucas.edu.cn/space/notpassport.mooc.ucas.edu.cn/home')).assertFalse();
      expect(isLoginRedirect('https://i.mooc.ucas.edu.cn/space/home?next=passport.mooc.ucas.edu.cn')).assertFalse();
    });
  });
}
