import localUnitTest from './LocalUnit.test';
import cookieUtilTest from './CookieUtil.test';
import redirectRulesTest from './RedirectRules.test';
import urlUtilTest from './UrlUtil.test';
import sessionManagerTest from './SessionManager.test';

export default function testsuite() {
  localUnitTest();
  cookieUtilTest();
  redirectRulesTest();
  urlUtilTest();
  sessionManagerTest();
}
