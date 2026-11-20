import { ItemType, PlacedItem, Plan, Point, Surface, surfaceFor, typeFor } from '../domain/LayoutModel';
import { LayoutIssue, hitItem, inspectLayout } from '../domain/LayoutRules';

const WALL: string = '#ACC4FF';
const GRID: string = '#2C3761';
const WARNING: string = '#FF817C';

@Component
export struct PlanView {
  @Prop @Watch('repaint') plan: Plan;
  @Prop @Watch('repaint') selected: string = '';
  @Prop interactive: boolean = false;
  onSelect: (id: string) => void = (id: string): void => {};
  onMove: (id: string, x: number, y: number) => void = (id: string, x: number, y: number): void => {};

  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private ready: boolean = false;
  private ratio: number = 1;
  private left: number = 0;
  private top: number = 0;
  private moving: string = '';
  private anchor: Point = { x: 0, y: 0 };
  private dragPosition: Point = { x: 0, y: 0 };

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.ready = true;
        this.repaint();
      })
      .onAreaChange((_old: Area, current: Area) => {
        this.canvasWidth = Number(current.width);
        this.canvasHeight = Number(current.height);
        this.repaint();
      })
      .priorityGesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 4 })
            .onActionStart((event: GestureEvent) => this.startDrag(event))
            .onActionUpdate((event: GestureEvent) => this.updateDrag(event))
            .onActionEnd(() => this.finishDrag())
            .onActionCancel(() => {
              this.moving = '';
              this.repaint();
            }),
          TapGesture().onAction((event: GestureEvent) => {
            if (this.interactive && event.fingerList.length > 0) {
              const finger = event.fingerList[0];
              this.onSelect(hitItem(this.plan.items, this.localPoint(finger.localX, finger.localY)));
            }
          })
        ),
        this.interactive ? GestureMask.Normal : GestureMask.IgnoreInternal
      )
  }

  private localPoint(x: number, y: number): Point {
    return { x: (x - this.left) / this.ratio, y: (y - this.top) / this.ratio };
  }

  private startDrag(event: GestureEvent): void {
    if (!this.interactive || event.fingerList.length === 0) {
      return;
    }
    const finger = event.fingerList[0];
    const point = this.localPoint(finger.localX - event.offsetX, finger.localY - event.offsetY);
    const id = hitItem(this.plan.items, point);
    const item = this.plan.items.find((it: PlacedItem) => it.id === id);
    if (item) {
      this.anchor = { x: item.x, y: item.y };
      this.moving = id;
      this.onSelect(id);
      this.updateDrag(event);
    }
  }

  private updateDrag(event: GestureEvent): void {
    if (this.moving === '') {
      return;
    }
    this.dragPosition = {
      x: Math.round(this.anchor.x + event.offsetX / this.ratio),
      y: Math.round(this.anchor.y + event.offsetY / this.ratio)
    };
    this.repaint();
  }

  private finishDrag(): void {
    if (this.moving !== '') {
      const id = this.moving;
      this.moving = '';
      this.onMove(id, this.dragPosition.x, this.dragPosition.y);
      this.repaint();
    }
  }

  private repaint(): void {
    if (!this.ready || this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return;
    }
    const c = this.context;
    const surface = surfaceFor(this.plan.surface);
    const inset = this.interactive ? 15 : 7;
    this.ratio = Math.min((this.canvasWidth - inset * 2) / surface.width, (this.canvasHeight - inset * 2) / surface.height);
    if (this.ratio <= 0) {
      return;
    }
    this.left = (this.canvasWidth - surface.width * this.ratio) / 2;
    this.top = (this.canvasHeight - surface.height * this.ratio) / 2;
    c.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    c.save();
    c.translate(this.left, this.top);
    c.scale(this.ratio, this.ratio);
    this.drawRoom(surface);
    const items = this.plan.items.map((item: PlacedItem): PlacedItem => {
      if (item.id === this.moving) {
        return { id: item.id, type: item.type, x: this.dragPosition.x, y: this.dragPosition.y, angle: item.angle, scale: item.scale };
      }
      return item;
    });
    let issues: LayoutIssue[] = [];
    if (this.interactive) {
      const preview: Plan = { id: this.plan.id, name: this.plan.name, surface: this.plan.surface, items: items };
      issues = inspectLayout(preview);
    }
    for (const item of items) {
      const conflicted = issues.some((issue: LayoutIssue) => issue.itemId === item.id || issue.otherId === item.id);
      this.drawItem(item, conflicted);
    }
    c.restore();
  }

  private line(x: number, y: number, toX: number, toY: number): void {
    const c = this.context;
    c.beginPath();
    c.moveTo(x, y);
    c.lineTo(toX, toY);
    c.stroke();
  }

  private drawRoom(surface: Surface): void {
    const c = this.context;
    const w = surface.width;
    const h = surface.height;
    c.fillStyle = '#1B2450';
    c.fillRect(0, 0, w, h);
    c.lineWidth = 1;
    for (let x = 24; x < w; x += 24) {
      c.strokeStyle = x % 96 === 0 ? '#46558B' : GRID;
      this.line(x, 0, x, h);
    }
    for (let y = 24; y < h; y += 24) {
      c.strokeStyle = y % 96 === 0 ? '#46558B' : GRID;
      this.line(0, y, w, y);
    }
    c.strokeStyle = WALL;
    c.lineWidth = 4;
    c.beginPath();
    c.moveTo(surface.door, h);
    c.lineTo(0, h);
    c.lineTo(0, 0);
    c.lineTo(w, 0);
    c.lineTo(w, h);
    c.lineTo(surface.door + surface.doorWidth, h);
    c.stroke();
    if (surface.id === 'dorm') {
      c.fillStyle = '#70D3FF';
      c.fillRect(w - 4, 56, 8, 126);
      c.strokeStyle = '#8DB6FF';
      c.lineWidth = 2;
      c.beginPath();
      c.arc(surface.door, h, surface.doorWidth, -Math.PI / 2, 0);
      c.stroke();
      this.line(surface.door, h, surface.door, h - surface.doorWidth);
    } else {
      c.fillStyle = '#948BFF';
      c.fillRect(0, 0, w, 10);
      c.strokeStyle = '#8DB6FF';
      c.lineWidth = 2;
      const entry = surface.door + surface.doorWidth / 2;
      this.line(entry, h + 13, entry, h - 15);
      this.line(entry, h - 15, entry - 8, h - 7);
      this.line(entry, h - 15, entry + 8, h - 7);
    }
    if (this.interactive && this.plan.items.length === 0) {
      c.font = 'bold 42px sans-serif';
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      c.fillStyle = '#CFD8FB';
      c.fillText('从下方选取物件开始布置', w / 2, h / 2);
    }
  }

  private drawItem(item: PlacedItem, conflicted: boolean): void {
    const type: ItemType = typeFor(item.type);
    const c = this.context;
    const active = this.interactive && item.id === this.selected;
    const w = type.width * item.scale;
    const h = type.height * item.scale;
    c.save();
    c.translate(item.x, item.y);
    c.rotate(item.angle * Math.PI / 180);
    c.fillStyle = conflicted ? '#FFAAA9' : type.color;
    c.fillRect(-w / 2, -h / 2, w, h);
    c.strokeStyle = conflicted ? WARNING : active ? '#F6FAFF' : '#5D6996';
    c.lineWidth = active || conflicted ? 3 : 1.6;
    c.strokeRect(-w / 2, -h / 2, w, h);
    if (this.interactive) {
      c.fillStyle = '#192240';
      c.font = 'bold ' + Math.min(39, 37 * item.scale) + 'px sans-serif';
      c.textAlign = 'center';
      c.textBaseline = 'middle';
      c.fillText(type.label, 0, 0);
      if (active) {
        c.fillStyle = conflicted ? WARNING : '#F6FAFF';
        c.fillRect(-w / 2 - 3.5, -h / 2 - 3.5, 7, 7);
        c.fillRect(w / 2 - 3.5, h / 2 - 3.5, 7, 7);
      }
    }
    c.restore();
  }
}
