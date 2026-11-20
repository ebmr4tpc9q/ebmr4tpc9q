import { MAX_ITEMS, PlacedItem, Plan, clonePlan, surfaceFor, typeFor } from '../domain/LayoutModel';
import { MAX_SCALE, MIN_SCALE } from '../domain/LayoutRules';

export interface TextStore {
  read(): Promise<string>;
  write(text: string): Promise<void>;
}

interface Archive {
  version: number;
  plans: Plan[];
}

export const MAX_PLANS: number = 30;

export function normalizeName(raw: string): string {
  const name = raw.trim();
  if (name.length < 1 || name.length > 24 || /[\u0000-\u001F]/.test(name)) {
    throw new Error('请输入 1～24 个字符的方案名称');
  }
  return name;
}

function validId(id: string): boolean {
  return typeof id === 'string' && /^[A-Za-z0-9-]{1,64}$/.test(id);
}

function validateItem(item: PlacedItem): void {
  if (!item || !validId(item.id) || !Number.isFinite(item.x) || !Number.isFinite(item.y) ||
    Math.abs(item.x) > 10000 || Math.abs(item.y) > 10000 ||
    !Number.isFinite(item.angle) || item.angle < 0 || item.angle >= 360 ||
    !Number.isFinite(item.scale) || item.scale < MIN_SCALE || item.scale > MAX_SCALE) {
    throw new Error('物件几何数据无效');
  }
  typeFor(item.type);
}

function validatePlan(plan: Plan): void {
  if (!plan || !validId(plan.id) || typeof plan.name !== 'string' || plan.name !== normalizeName(plan.name) ||
    !Array.isArray(plan.items) || plan.items.length > MAX_ITEMS) {
    throw new Error('方案数据无效');
  }
  surfaceFor(plan.surface);
  const itemIds = new Set<string>();
  for (const item of plan.items) {
    validateItem(item);
    if (itemIds.has(item.id)) {
      throw new Error('方案中存在重复物件');
    }
    itemIds.add(item.id);
  }
}

export function decodeArchive(text: string): Plan[] {
  if (text === '') {
    return [];
  }
  const value = JSON.parse(text) as Archive;
  if (!value || value.version !== 1 || !Array.isArray(value.plans) || value.plans.length > MAX_PLANS) {
    throw new Error('方案库格式无效');
  }
  const ids = new Set<string>();
  for (const plan of value.plans) {
    validatePlan(plan);
    if (ids.has(plan.id)) {
      throw new Error('方案 ID 重复');
    }
    ids.add(plan.id);
  }
  return value.plans.map(clonePlan);
}

export class PlanRepository {
  private store: TextStore;
  private plans: Plan[] = [];
  private ready: boolean = false;
  private busy: boolean = false;

  constructor(store: TextStore) {
    this.store = store;
  }

  async load(): Promise<Plan[]> {
    if (this.busy) {
      throw new Error('方案库正在操作');
    }
    this.busy = true;
    this.ready = false;
    try {
      this.plans = decodeArchive(await this.store.read());
      this.ready = true;
      return this.plans.map(clonePlan);
    } finally {
      this.busy = false;
    }
  }

  async save(draft: Plan, rawName: string): Promise<Plan[]> {
    if (!this.ready || this.busy) {
      throw new Error('方案库当前不可写');
    }
    const plan = clonePlan(draft);
    plan.name = normalizeName(rawName);
    validatePlan(plan);
    const remaining = this.plans.filter((other: Plan) => other.id !== plan.id);
    if (remaining.length >= MAX_PLANS) {
      throw new Error('方案库已满，最多保存 30 份');
    }
    const next = [plan].concat(remaining);
    const payload: Archive = { version: 1, plans: next };
    this.busy = true;
    try {
      await this.store.write(JSON.stringify(payload));
      this.plans = next;
      return this.plans.map(clonePlan);
    } finally {
      this.busy = false;
    }
  }
}
