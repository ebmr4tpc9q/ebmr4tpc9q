import { PlacedItem, cloneItem } from './LayoutModel';

export class LayoutHistory {
  private past: PlacedItem[][] = [];
  private future: PlacedItem[][] = [];
  private current: PlacedItem[] = [];

  constructor(items: PlacedItem[]) {
    this.current = items.map(cloneItem);
  }

  canUndo(): boolean {
    return this.past.length > 0;
  }

  canRedo(): boolean {
    return this.future.length > 0;
  }

  apply(items: PlacedItem[]): boolean {
    if (JSON.stringify(items) === JSON.stringify(this.current)) {
      return false;
    }
    this.past.push(this.current);
    if (this.past.length > 60) {
      this.past.shift();
    }
    this.current = items.map(cloneItem);
    this.future = [];
    return true;
  }

  undo(): PlacedItem[] | undefined {
    const previous = this.past.pop();
    if (previous === undefined) {
      return undefined;
    }
    this.future.push(this.current);
    this.current = previous;
    return this.current.map(cloneItem);
  }

  redo(): PlacedItem[] | undefined {
    const next = this.future.pop();
    if (next === undefined) {
      return undefined;
    }
    this.past.push(this.current);
    this.current = next;
    return this.current.map(cloneItem);
  }
}
