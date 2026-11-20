export interface Point {
  x: number;
  y: number;
}

export interface Surface {
  id: string;
  label: string;
  description: string;
  width: number;
  height: number;
  door: number;
  doorWidth: number;
}

export interface ItemType {
  id: string;
  label: string;
  color: string;
  width: number;
  height: number;
}

export interface PlacedItem {
  id: string;
  type: string;
  x: number;
  y: number;
  scale: number;
  angle: number;
}

export interface Plan {
  id: string;
  name: string;
  surface: string;
  items: PlacedItem[];
}

export const SURFACES: Surface[] = [
  { id: 'dorm', label: '双人宿舍', description: '侧窗 · 左侧入口', width: 480, height: 360, door: 42, doorWidth: 86 },
  { id: 'booth', label: '社团展位', description: '上方展示墙 · 中央入口', width: 420, height: 320, door: 146, doorWidth: 128 }
];

export const CATALOG: ItemType[] = [
  { id: 'bed', label: '床', color: '#9DB9FF', width: 148, height: 68 },
  { id: 'desk', label: '书桌', color: '#FFC376', width: 105, height: 51 },
  { id: 'cabinet', label: '收纳柜', color: '#C8AFF8', width: 76, height: 42 },
  { id: 'chair', label: '椅子', color: '#88DBC9', width: 45, height: 45 },
  { id: 'counter', label: '展台', color: '#FCA9A1', width: 96, height: 58 },
  { id: 'board', label: '展板', color: '#E4DC88', width: 112, height: 29 }
];

export const MAX_ITEMS: number = 40;

export function surfaceFor(id: string): Surface {
  const found = SURFACES.find((surface: Surface) => surface.id === id);
  if (!found) {
    throw new Error('未知底图');
  }
  return found;
}

export function typeFor(id: string): ItemType {
  const found = CATALOG.find((type: ItemType) => type.id === id);
  if (!found) {
    throw new Error('未知物件');
  }
  return found;
}

export function cloneItem(item: PlacedItem): PlacedItem {
  return { id: item.id, type: item.type, x: item.x, y: item.y, angle: item.angle, scale: item.scale };
}

export function clonePlan(plan: Plan): Plan {
  return { id: plan.id, name: plan.name, surface: plan.surface, items: plan.items.map(cloneItem) };
}

let counter: number = 0;

export function makeId(): string {
  counter += 1;
  return Date.now().toString(36) + '-' + counter.toString(36) + '-' + Math.random().toString(36).slice(2, 9);
}
