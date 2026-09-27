import { describe, it, expect } from '@ohos/hypium';
import { SessionManager, ServerCheckStatus } from '../main/ets/auth/SessionManager';

export default function sessionManagerTest() {
  describe('SessionManager notifications', () => {
    it('keeps notifying after one listener throws and respects unsubscribe', 0, () => {
      const service: SessionManager = SessionManager.get();
      let calls: number = 0;
      const failing: () => void = () => { throw new Error('test listener failure'); };
      const recording: () => void = () => { calls++; };
      service.subscribe(failing);
      service.subscribe(recording);
      service.setServerCheck(ServerCheckStatus.PASSED);
      expect(calls).assertEqual(1);
      expect(service.snapshot().serverCheck).assertEqual(ServerCheckStatus.PASSED);
      service.unsubscribe(failing);
      service.unsubscribe(recording);
      service.setServerCheck(ServerCheckStatus.UNCHECKED);
      expect(calls).assertEqual(1);
    });
  });
}
