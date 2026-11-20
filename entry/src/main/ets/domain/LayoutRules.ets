import { ItemType, PlacedItem, Plan, Point, Surface, cloneItem, surfaceFor, typeFor } from './LayoutModel';

const EPSILON: number = 0.000001;
const OVERLAP_LIMIT: number = 0.20;
export const MIN_SCALE: number = 0.5;
export const MAX_SCALE: number = 1.8;

export interface LayoutIssue {
  itemId: string;
  otherId: string;
  kind: string;
}

export function itemCorners(item: PlacedItem): Point[] {
  const type: ItemType = typeFor(item.type);
  const w = type.width * item.scale / 2;
  const h = type.height * item.scale / 2;
  const radians = item.angle * Math.PI / 180;
  const c = Math.cos(radians);
  const s = Math.sin(radians);
  const offsets: Point[] = [{ x: -w, y: -h }, { x: w, y: -h }, { x: w, y: h }, { x: -w, y: h }];
  return offsets.map((p: Point): Point => {
    return { x: item.x + p.x * c - p.y * s, y: item.y + p.x * s + p.y * c };
  });
}

function side(a: Point, b: Point, p: Point): number {
  return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

export function polygonOverlap(subject: Point[], clip: Point[]): number {
  let output = subject.slice();
  for (let i = 0; i < clip.length && output.length > 0; i++) {
    const a = clip[i];
    const b = clip[(i + 1) % clip.length];
    const input = output;
    output = [];
    let previous = input[input.length - 1];
    let before = side(a, b, previous);
    for (const current of input) {
      const after = side(a, b, current);
      if ((before >= -EPSILON) !== (after >= -EPSILON)) {
        const t = Math.max(0, Math.min(1, before / (before - after)));
        output.push({ x: previous.x + t * (current.x - previous.x), y: previous.y + t * (current.y - previous.y) });
      }
      if (after >= -EPSILON) {
        output.push(current);
      }
      previous = current;
      before = after;
    }
  }
  let twiceArea = 0;
  for (let i = 0; i < output.length; i++) {
    const a = output[i];
    const b = output[(i + 1) % output.length];
    twiceArea += a.x * b.y - a.y * b.x;
  }
  return Math.abs(twiceArea) / 2;
}

function outside(points: Point[], surface: Surface): boolean {
  return points.some((p: Point) => p.x < -EPSILON || p.y < -EPSILON ||
    p.x > surface.width + EPSILON || p.y > surface.height + EPSILON);
}

function itemArea(item: PlacedItem): number {
  const type = typeFor(item.type);
  return type.width * type.height * item.scale * item.scale;
}

export function inspectLayout(plan: Plan): LayoutIssue[] {
  const surface = surfaceFor(plan.surface);
  const polygons = plan.items.map(itemCorners);
  const areas = plan.items.map(itemArea);
  const issues: LayoutIssue[] = [];
  for (let i = 0; i < polygons.length; i++) {
    if (outside(polygons[i], surface)) {
      issues.push({ itemId: plan.items[i].id, otherId: '', kind: 'boundary' });
    }
    for (let j = 0; j < i; j++) {
      const intersection = polygonOverlap(polygons[i], polygons[j]);
      if (intersection + EPSILON >= OVERLAP_LIMIT * Math.min(areas[i], areas[j])) {
        issues.push({ itemId: plan.items[i].id, otherId: plan.items[j].id, kind: 'overlap' });
      }
    }
  }
  return issues;
}

export function hitItem(items: PlacedItem[], point: Point): string {
  for (let i = items.length - 1; i >= 0; i--) {
    const polygon = itemCorners(items[i]);
    const inside = polygon.every((a: Point, index: number) =>
      side(a, polygon[(index + 1) % polygon.length], point) >= -EPSILON);
    if (inside) {
      return items[i].id;
    }
  }
  return '';
}

export function transformed(item: PlacedItem, angleDelta: number, scaleDelta: number): PlacedItem {
  const next = cloneItem(item);
  next.angle = ((item.angle + angleDelta) % 360 + 360) % 360;
  next.scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, Math.round((item.scale + scaleDelta) * 100) / 100));
  return next;
}

export function placeItem(plan: Plan, typeId: string, id: string): PlacedItem {
  const type = typeFor(typeId);
  const surface = surfaceFor(plan.surface);
  const proposed: PlacedItem = { id: id, type: typeId, x: surface.width / 2, y: surface.height / 2, angle: 0, scale: 1 };
  const existing = plan.items.map(itemCorners);
  for (let y = 22 + type.height / 2; y <= surface.height - type.height / 2 - 20; y += 22) {
    for (let x = 22 + type.width / 2; x <= surface.width - type.width / 2 - 20; x += 22) {
      const candidate = cloneItem(proposed);
      candidate.x = x;
      candidate.y = y;
      const corners = itemCorners(candidate);
      if (existing.every((polygon: Point[]) => polygonOverlap(corners, polygon) <= EPSILON)) {
        return candidate;
      }
    }
  }
  return proposed;
}
