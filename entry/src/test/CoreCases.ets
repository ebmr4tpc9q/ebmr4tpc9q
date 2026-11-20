import { PlanRepository, TextStore, decodeArchive, normalizeName } from '../main/ets/data/PlanRepository';
import { LayoutHistory } from '../main/ets/domain/LayoutHistory';
import { CATALOG, PlacedItem, Plan, SURFACES, clonePlan } from '../main/ets/domain/LayoutModel';
import { hitItem, inspectLayout, placeItem, transformed } from '../main/ets/domain/LayoutRules';

interface CoreCase {
  id: string;
  run: () => Promise<void>;
}

function check(condition: boolean, explanation: string): void {
  if (!condition) {
    throw new Error(explanation);
  }
}

function chair(id: string, x: number, y: number, angle: number = 0): PlacedItem {
  return { id: id, type: 'chair', x: x, y: y, angle: angle, scale: 1 };
}

function plan(id: string = 'alpha', items: PlacedItem[] = []): Plan {
  return { id: id, name: '原布局', surface: 'dorm', items: items };
}

class MemoryStore implements TextStore {
  payload: string = '';
  fail: boolean = false;

  async read(): Promise<string> {
    return this.payload;
  }

  async write(text: string): Promise<void> {
    if (this.fail) {
      throw new Error('Mock write failure');
    }
    this.payload = text;
  }
}

export function coreCases(): CoreCase[] {
  const cases: CoreCase[] = [
    { id: 'C01 templates-and-catalog', run: async (): Promise<void> => {
      check(SURFACES.length === 2 && CATALOG.length === 6, 'Expected two spaces and six pieces');
      let work = plan();
      for (const type of CATALOG) {
        work.items.push(placeItem(work, type.id, type.id));
      }
      check(inspectLayout(work).length === 0, 'Starter placement had a conflict');
    } },
    { id: 'C02 topmost-rotated-hit', run: async (): Promise<void> => {
      const lower = chair('under', 100, 100);
      const upper = chair('top', 100, 100, 45);
      check(hitItem([lower, upper], { x: 100, y: 100 }) === 'top', 'Stack order was ignored');
      check(hitItem([upper], { x: 128, y: 128 }) === '', 'Clicked outside the rotated shape');
    } },
    { id: 'C03 touching-wall-and-rotated-boundary', run: async (): Promise<void> => {
      check(inspectLayout(plan('alpha', [chair('a', 22.5, 90)])).length === 0, 'Touching wall must pass');
      const issues = inspectLayout(plan('alpha', [chair('a', 22.5, 90, 45)]));
      check(issues.length === 1 && issues[0].kind === 'boundary', 'Rotated corner should leave the room');
    } },
    { id: 'C04 overlap-threshold', run: async (): Promise<void> => {
      const a = chair('a', 100, 100);
      check(inspectLayout(plan('p', [a, chair('b', 145, 100)])).length === 0, 'Touching edges must pass');
      check(inspectLayout(plan('p', [a, chair('b', 137, 100)])).length === 0, 'Under 20% must pass');
      check(inspectLayout(plan('p', [a, chair('b', 136, 100)])).length === 1, 'Exactly 20% must warn');
    } },
    { id: 'C05 scale-rotation-limits', run: async (): Promise<void> => {
      const initial = chair('a', 100, 100);
      const small = transformed(initial, -15, -2);
      const large = transformed(initial, 375, 2);
      check(small.angle === 345 && small.scale === 0.5, 'Expected normalized angle and lower bound');
      check(large.angle === 15 && large.scale === 1.8 && initial.scale === 1, 'Upper bound or immutability failed');
    } },
    { id: 'C06 edit-undo-redo-and-branch', run: async (): Promise<void> => {
      const initial = chair('a', 100, 100);
      const history = new LayoutHistory([initial]);
      check(!history.apply([initial]), 'No-op must not create a step');
      check(history.apply([]), 'Expected delete operation');
      const restored = history.undo();
      check(restored !== undefined && restored.length === 1, 'Undo did not restore deletion');
      const redone = history.redo();
      check(redone !== undefined && redone.length === 0, 'Redo did not delete again');
      history.undo();
      history.apply([chair('a', 120, 100)]);
      check(!history.canRedo(), 'New action must discard redo');
    } },
    { id: 'C07 save-three-and-reopen', run: async (): Promise<void> => {
      const store = new MemoryStore();
      const repo = new PlanRepository(store);
      await repo.load();
      await repo.save(plan('d1', [chair('a', 102, 116, 15)]), '  Dorm Day  ');
      await repo.save(plan('b1'), 'Expo Open');
      await repo.save(plan('d2'), 'Dorm Quiet');
      const reopened = new PlanRepository(store);
      const previous = await reopened.load();
      const item = previous[2].items[0];
      check(previous.length === 3 && previous[2].name === 'Dorm Day' &&
        item.x === 102 && item.y === 116 && item.angle === 15, 'Recovered plan differs');
      const changed = clonePlan(previous[2]);
      changed.items[0].scale = 1.1;
      const saved = await reopened.save(changed, previous[2].name);
      check(saved.length === 3 && saved[0].id === 'd1' && saved[0].items[0].scale === 1.1, 'Upsert duplicated a plan');
    } },
    { id: 'C08 blank-name', run: async (): Promise<void> => {
      let rejected = false;
      try {
        normalizeName('   ');
      } catch (error) {
        rejected = true;
      }
      check(rejected && normalizeName('123456789012345678901234').length === 24, 'Name boundaries failed');
    } },
    { id: 'C09 corrupt-archive-blocks-overwrite', run: async (): Promise<void> => {
      const store = new MemoryStore();
      store.payload = '{"version":2,"plans":[]}';
      const repo = new PlanRepository(store);
      let blocked = 0;
      try {
        await repo.load();
      } catch (error) {
        blocked++;
      }
      try {
        await repo.save(plan(), '新布局');
      } catch (error) {
        blocked++;
      }
      check(blocked === 2 && store.payload === '{"version":2,"plans":[]}', 'Corrupt archive must remain untouched');
    } },
    { id: 'C10 flush-failure-and-retry', run: async (): Promise<void> => {
      const store = new MemoryStore();
      const repo = new PlanRepository(store);
      await repo.load();
      await repo.save(plan('first'), 'First');
      const before = store.payload;
      store.fail = true;
      let failed = false;
      try {
        await repo.save(plan('second'), 'Second');
      } catch (error) {
        failed = true;
      }
      check(failed && store.payload === before, 'A failed write changed the stored archive');
      store.fail = false;
      check((await repo.save(plan('third'), 'Third')).length === 2, 'Failed plan leaked into the next save');
      check((await repo.save(plan('second'), 'Second')).length === 3, 'Retry failed');
    } },
    { id: 'C11 reject-duplicate-item-ids', run: async (): Promise<void> => {
      const archive = JSON.stringify({ version: 1, plans: [plan('d1', [chair('a', 40, 40), chair('a', 80, 80)])] });
      let rejected = false;
      try {
        decodeArchive(archive);
      } catch (error) {
        rejected = true;
      }
      check(rejected, 'Duplicate IDs should be invalid');
    } },
    { id: 'C12 full-library-allows-update', run: async (): Promise<void> => {
      const store = new MemoryStore();
      const repo = new PlanRepository(store);
      await repo.load();
      for (let i = 0; i < 30; i++) {
        await repo.save(plan('p-' + i), 'Plan ' + i);
      }
      let rejected = false;
      try {
        await repo.save(plan('p-30'), 'Plan 31');
      } catch (error) {
        rejected = true;
      }
      check(rejected, 'A 31st plan must be rejected');
      check((await repo.save(plan('p-0'), 'Updated')).length === 30, 'Updating at capacity must succeed');
    } }
  ];
  return cases;
}
