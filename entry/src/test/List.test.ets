import { describe, it } from '@ohos/hypium';
import { coreCases } from './CoreCases';

export default function tests(): void {
  describe('CornerPlanCore', () => {
    for (const testCase of coreCases()) {
      it(testCase.id, 0, async () => {
        await testCase.run();
      });
    }
  });
}
