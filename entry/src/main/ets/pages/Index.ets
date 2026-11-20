import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CATALOG, ItemType, MAX_ITEMS, PlacedItem, Plan, SURFACES, Surface, clonePlan, makeId, surfaceFor, typeFor } from '../domain/LayoutModel';
import { LayoutHistory } from '../domain/LayoutHistory';
import { LayoutIssue, inspectLayout, placeItem, transformed } from '../domain/LayoutRules';
import { PlanRepository, normalizeName } from '../data/PlanRepository';
import { PreferencesStore } from '../data/PreferencesStore';
import { PlanView } from './PlanView';

const INK: string = '#161A32';
const MUTED: string = '#535B79';
const ACCENT: string = '#5548E6';
const NAVY: string = '#111634';
const ACTIVE: string = '#E9E7FF';
const ERROR: string = '#AA354E';
const LINE: string = '#DDE0F0';
const PAPER: string = '#F6F7FC';
const WHITE: string = '#FFFFFF';

function blankPlan(surfaceId: string): Plan {
  return { id: makeId(), name: '', surface: surfaceId, items: [] };
}

@Entry
@Component
struct Index {
  @State private screen: string = 'home';
  @State private plan: Plan = blankPlan('dorm');
  @State private plans: Plan[] = [];
  @State private selected: string = '';
  @State private issues: LayoutIssue[] = [];
  @State private canUndo: boolean = false;
  @State private canRedo: boolean = false;
  @State private dirty: boolean = false;
  @State private ready: boolean = false;
  @State private busy: boolean = true;
  @State private loadError: string = '';
  @State private message: string = '';
  @State private dialog: string = '';
  @State private dialogError: string = '';
  @State private pendingName: string = '';
  private history: LayoutHistory = new LayoutHistory([]);
  private baseline: string = '';
  private repo?: PlanRepository;
  private nextScreen: string = 'home';

  aboutToAppear(): void {
    this.initialize();
  }

  onBackPress(): boolean {
    if (this.dialog !== '') {
      if (!this.busy) {
        this.dialog = '';
      }
      return true;
    }
    if (this.screen !== 'home') {
      this.go('home');
      return true;
    }
    return false;
  }

  private async initialize(): Promise<void> {
    this.busy = true;
    this.loadError = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await PreferencesStore.open(context);
      this.repo = new PlanRepository(store);
      this.plans = await this.repo.load();
      this.ready = true;
      hilog.info(0x0101, 'CornerPlan', 'Loaded %{public}d local plans', this.plans.length);
    } catch (error) {
      this.ready = false;
      this.loadError = '方案库读取失败，暂时无法保存。可重试读取。';
      hilog.error(0x0101, 'CornerPlan', 'Plan load failed: %{public}s', String(error));
    } finally {
      this.busy = false;
    }
  }

  private show(screen: string): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.screen = screen;
    });
  }

  private go(screen: string): void {
    if (this.screen === screen || this.busy) {
      return;
    }
    if (this.screen === 'editor' && this.dirty) {
      this.nextScreen = screen;
      this.dialog = 'leave';
    } else {
      this.show(screen);
    }
  }

  private edit(plan: Plan): void {
    this.plan = clonePlan(plan);
    this.history = new LayoutHistory(this.plan.items);
    this.baseline = JSON.stringify(this.plan.items);
    this.selected = '';
    this.message = '';
    this.updateIndicators();
    this.show('editor');
  }

  private updateIndicators(): void {
    this.issues = inspectLayout(this.plan);
    this.canUndo = this.history.canUndo();
    this.canRedo = this.history.canRedo();
    this.dirty = JSON.stringify(this.plan.items) !== this.baseline;
  }

  private updateItems(items: PlacedItem[]): void {
    this.plan = { id: this.plan.id, name: this.plan.name, surface: this.plan.surface, items: items };
    if (!items.some((item: PlacedItem) => item.id === this.selected)) {
      this.selected = '';
    }
    this.message = '';
    this.updateIndicators();
  }

  private commit(items: PlacedItem[]): void {
    if (this.history.apply(items)) {
      this.updateItems(items);
    }
  }

  private add(type: ItemType): void {
    if (this.plan.items.length >= MAX_ITEMS) {
      this.message = '每份方案最多放置 40 件物件';
      return;
    }
    const item = placeItem(this.plan, type.id, makeId());
    this.selected = item.id;
    this.commit(this.plan.items.concat([item]));
  }

  private move(id: string, x: number, y: number): void {
    this.commit(this.plan.items.map((item: PlacedItem): PlacedItem => {
      if (item.id === id) {
        return { id: item.id, type: item.type, x: x, y: y, angle: item.angle, scale: item.scale };
      }
      return item;
    }));
  }

  private adjust(angle: number, scale: number): void {
    this.commit(this.plan.items.map((item: PlacedItem) =>
      item.id === this.selected ? transformed(item, angle, scale) : item));
  }

  private historyStep(undo: boolean): void {
    const items = undo ? this.history.undo() : this.history.redo();
    if (items !== undefined) {
      this.updateItems(items);
    }
  }

  private selectedSummary(): string {
    const item = this.plan.items.find((it: PlacedItem) => it.id === this.selected);
    if (!item) {
      return '点选物件后可调整';
    }
    return typeFor(item.type).label + '  /  ' + item.angle + '°  /  ' + item.scale.toFixed(1) + '×';
  }

  private layoutStatus(): string {
    if (this.issues.length === 0) {
      return '布局无冲突';
    }
    const boundary = this.issues.filter((issue: LayoutIssue) => issue.kind === 'boundary').length;
    return '越界 ' + boundary + ' 件  ·  重叠 ' + (this.issues.length - boundary) + ' 组';
  }

  private prepareSave(): void {
    if (this.ready) {
      this.pendingName = this.plan.name;
      this.dialogError = '';
      this.dialog = 'save';
    } else {
      this.message = '方案库未就绪，请返回首页重试读取';
    }
  }

  private async save(): Promise<void> {
    if (!this.repo || this.busy) {
      return;
    }
    let name: string;
    try {
      name = normalizeName(this.pendingName);
    } catch (error) {
      this.dialogError = '请输入 1～24 个字符的方案名称';
      return;
    }
    this.busy = true;
    this.dialogError = '';
    try {
      this.plans = await this.repo.save(this.plan, name);
      this.plan = { id: this.plan.id, name: name, surface: this.plan.surface, items: this.plan.items };
      this.baseline = JSON.stringify(this.plan.items);
      this.dirty = false;
      this.dialog = '';
      this.message = '已保存「' + name + '」';
      hilog.info(0x0101, 'CornerPlan', 'Saved %{public}s with %{public}d items', this.plan.id, this.plan.items.length);
    } catch (error) {
      this.dialogError = '保存失败。检查方案库容量或稍后重试。';
      hilog.error(0x0101, 'CornerPlan', 'Plan save failed: %{public}s', String(error));
    } finally {
      this.busy = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.Header()
        if (this.screen === 'home') {
          Scroll() {
            this.Home()
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .transition(TransitionEffect.OPACITY)
        } else if (this.screen === 'editor') {
          Scroll() {
            this.Editor()
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .transition(TransitionEffect.OPACITY)
        } else {
          Scroll() {
            this.Library()
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .transition(TransitionEffect.OPACITY)
        }
        this.Navigation()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(PAPER)
      if (this.dialog !== '') {
        this.Modal()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }

  @Builder
  Header() {
    Row({ space: 10 }) {
      Image($r('app.media.app_icon')).width(29).height(29).borderRadius(7)
      Text('角落计划').fontColor(WHITE).fontWeight(FontWeight.Bold).fontSize(19).layoutWeight(1)
      if (this.screen === 'editor') {
        Text('平面编辑').fontSize(12).fontColor('#C5CEFF')
      }
    }
    .width('100%').height(48).padding({ left: 16, right: 16 }).backgroundColor(NAVY)
  }

  @Builder
  Navigation() {
    Row({ space: 8 }) {
      Button('首页', { type: ButtonType.Normal })
        .layoutWeight(1).height(40).fontSize(14).borderRadius(6)
        .backgroundColor(this.screen === 'home' ? ACTIVE : WHITE)
        .fontColor(this.screen === 'home' ? ACCENT : MUTED)
        .onClick(() => this.go('home'))
      Button('方案库 ' + this.plans.length, { type: ButtonType.Normal })
        .layoutWeight(1).height(40).fontSize(14).borderRadius(6)
        .backgroundColor(this.screen === 'library' ? ACTIVE : WHITE)
        .fontColor(this.screen === 'library' ? ACCENT : MUTED)
        .onClick(() => this.go('library'))
    }
    .width('100%').height(55).padding({ left: 14, right: 14 })
    .backgroundColor(WHITE).borderWidth({ top: 1 }).borderColor(LINE)
  }

  @Builder
  Home() {
    Column({ space: 20 }) {
      Column({ space: 7 }) {
        Text('选一张底图').fontSize(34).fontWeight(FontWeight.Bold).fontColor(INK)
        Text('在平面图上布置物件，保存后可随时继续编辑。').fontSize(14).fontColor(MUTED)
      }
      .width('100%').alignItems(HorizontalAlign.Start)

      Row({ space: 10 }) {
        ForEach(SURFACES, (surface: Surface) => {
          Column() {
            Stack({ alignContent: Alignment.BottomStart }) {
              Column() {
                PlanView({ plan: { id: surface.id, name: '', surface: surface.id, items: [] } })
              }
              .width('100%').height(131).padding({ bottom: 16, left: 5, right: 5 })
              .hitTestBehavior(HitTestMode.None)
              Text(surface.width + ' × ' + surface.height)
                .fontSize(10).fontFamily('monospace').fontColor('#C6D1FF')
                .padding({ left: 10, bottom: 7 })
            }
            .width('100%').backgroundColor(NAVY)
            Column({ space: 5 }) {
              Row() {
                Text(surface.label).fontSize(16).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
                Text('↗').fontSize(16).fontColor(ACCENT)
              }
              .width('100%')
              Text(surface.description).fontSize(11).fontColor(MUTED).width('100%')
            }
            .padding(10).width('100%').alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1).backgroundColor(WHITE).borderRadius(7).clip(true)
          .border({ width: 1, color: LINE }).onClick(() => this.edit(blankPlan(surface.id)))
        }, (surface: Surface) => surface.id)
      }
      .width('100%')
      if (this.loadError !== '') {
        Text(this.loadError).fontSize(14).fontColor(ERROR).width('100%')
        Button('重试读取').backgroundColor(ACCENT).onClick(() => this.initialize()).enabled(!this.busy)
      }
    }
    .width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 16, right: 16, bottom: 20, top: 26 })
  }

  @Builder
  Editor() {
    Column({ space: 9 }) {
      Row({ space: 6 }) {
        Column({ space: 3 }) {
          Text(this.plan.name || '新建方案').fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(surfaceFor(this.plan.surface).label + '  ·  ' + this.plan.items.length + ' 件物件' +
            (this.dirty ? '  ·  有改动' : '')).fontSize(12).fontColor(MUTED)
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('保存方案', { type: ButtonType.Normal }).height(38).borderRadius(6).fontSize(14)
          .fontColor(WHITE).backgroundColor(ACCENT).enabled(!this.busy).onClick(() => this.prepareSave())
      }
      .width('100%')
      if (this.message !== '') {
        Text(this.message).fontSize(13).fontColor(ACCENT).padding(6).width('100%')
          .backgroundColor(ACTIVE).borderRadius(4)
      }

      Column() {
        Row() {
          Row().width(7).height(7).borderRadius(3.5)
            .backgroundColor(this.issues.length === 0 ? '#8BD6FF' : '#FFA19C')
          Blank().width(7)
          Text(this.layoutStatus()).fontSize(12).fontWeight(FontWeight.Medium).layoutWeight(1)
            .fontColor(this.issues.length === 0 ? '#D5E1FF' : '#FFB0A8')
          Text('拖动布置').fontSize(12).fontColor('#BAC6F0')
        }
        .width('100%').height(30).padding({ left: 12, right: 12 })
        .backgroundColor('#202956')
        Column() {
          PlanView({
            plan: this.plan, selected: this.selected, interactive: true,
            onSelect: (id: string) => { this.selected = id; },
            onMove: (id: string, x: number, y: number) => this.move(id, x, y)
          })
        }
        .id('editor-canvas').width('100%').aspectRatio(1.30)
        Row() {
          Text(surfaceFor(this.plan.surface).width + ' × ' + surfaceFor(this.plan.surface).height)
            .fontSize(10).fontFamily('monospace').fontColor('#C6D1FF').layoutWeight(1)
          Text('底图坐标').fontSize(10).fontColor('#C6D1FF')
        }
        .width('100%').height(22).padding({ left: 12, right: 12 })
      }
      .width('100%').backgroundColor(NAVY).borderRadius(7).clip(true)

      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(this.selectedSummary()).fontColor(INK).fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
          ToolButton({ label: '撤销', available: this.canUndo, execute: () => this.historyStep(true) })
          ToolButton({ label: '重做', available: this.canRedo, execute: () => this.historyStep(false) })
        }
        .width('100%')
        Row({ space: 5 }) {
          ToolButton({ label: '转 −15°', available: this.selected !== '', execute: () => this.adjust(-15, 0) })
          ToolButton({ label: '转 +15°', available: this.selected !== '', execute: () => this.adjust(15, 0) })
          ToolButton({ label: '缩小', available: this.selected !== '', execute: () => this.adjust(0, -0.1) })
          ToolButton({ label: '放大', available: this.selected !== '', execute: () => this.adjust(0, 0.1) })
          ToolButton({ label: '删除', available: this.selected !== '', execute: () => {
            this.commit(this.plan.items.filter((it: PlacedItem) => it.id !== this.selected));
          } })
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%').padding(7).backgroundColor(WHITE).borderRadius(5)
      .border({ width: 1, color: LINE })

      Text('添加物件').width('100%').fontSize(14).fontColor(INK).fontWeight(FontWeight.Bold)
      this.PaletteRow(CATALOG.slice(0, 3))
      this.PaletteRow(CATALOG.slice(3))
    }
    .width('100%').constraintSize({ maxWidth: 600 }).padding({ left: 12, right: 12, top: 10, bottom: 12 })
  }

  @Builder
  PaletteRow(types: ItemType[]) {
    Row({ space: 6 }) {
      ForEach(types, (type: ItemType) => {
        Row({ space: 5 }) {
          Stack() {
            Row()
              .width(11 + type.width / 15).height(5 + type.height / 8)
              .backgroundColor(type.color).border({ width: 1, color: '#7B84AC' })
          }
          .width(24)
          Text(type.label).fontSize(12).fontColor(INK).layoutWeight(1).maxLines(1)
          Text('+').fontSize(15).fontColor(ACCENT)
        }
        .layoutWeight(1).height(38).padding({ left: 6, right: 7 }).backgroundColor(WHITE)
        .borderRadius(5).border({ width: 1, color: LINE }).onClick(() => this.add(type))
      }, (type: ItemType) => type.id)
    }
    .width('100%')
  }

  @Builder
  Library() {
    Column({ space: 15 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text('本地方案库').fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('已保存 ' + this.plans.length + ' / 30 份').fontSize(13).fontColor(MUTED)
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('新建空间', { type: ButtonType.Normal }).height(36).borderRadius(6)
          .backgroundColor(ACCENT).fontSize(13).onClick(() => this.go('home'))
      }
      .width('100%')
      if (this.plans.length === 0) {
        Text(this.busy ? '正在读取方案…' : this.loadError || '还没有方案。从首页选择底图，新建并保存一份布局。')
          .fontSize(14).fontColor(MUTED).width('100%').padding(16)
          .backgroundColor(WHITE).borderRadius(6).border({ width: 1, color: LINE })
      }
      GridRow({ columns: 2, gutter: 9 }) {
        ForEach(this.plans, (plan: Plan) => {
          GridCol() {
            Column() {
              Column() {
                PlanView({ plan: plan })
              }
              .width('100%').aspectRatio(1.48).padding(4).hitTestBehavior(HitTestMode.None)
              .backgroundColor(NAVY)
              Column({ space: 5 }) {
                Row() {
                  Text(plan.name).fontSize(14).fontWeight(FontWeight.Bold).fontColor(INK)
                    .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('↗').fontSize(15).fontColor(ACCENT)
                }
                .width('100%')
                Text(surfaceFor(plan.surface).label + ' · ' + plan.items.length + ' 件')
                  .fontSize(11).fontColor(MUTED).width('100%')
              }
              .width('100%').padding(8)
            }
            .width('100%').backgroundColor(WHITE).borderRadius(6).clip(true)
            .border({ width: 1, color: LINE }).onClick(() => this.edit(plan))
          }
        }, (plan: Plan) => plan.id + JSON.stringify(plan))
      }
      .width('100%')
    }
    .width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 16, right: 16, top: 22, bottom: 16 })
  }

  @Builder
  Modal() {
    Column() {
      Column({ space: 12 }) {
        Text(this.dialog === 'save' ? '保存方案' : '放弃未保存的修改？')
          .fontSize(21).fontColor(INK).fontWeight(FontWeight.Bold).width('100%')
        if (this.dialog === 'save') {
          TextInput({ text: this.pendingName, placeholder: '输入方案名称' })
            .onChange((value: string) => { this.pendingName = value; this.dialogError = ''; })
            .id('plan-name').maxLength(24).fontSize(16).height(46).enabled(!this.busy)
          if (this.issues.length > 0) {
            Text('当前存在布局冲突，仍可保存草案。').fontSize(13).fontColor(ERROR).width('100%')
          }
          if (this.dialogError !== '') {
            Text(this.dialogError).fontSize(13).fontColor(ERROR).width('100%')
          }
        } else {
          Text('已保存的方案仍可在方案库中打开。').fontSize(14).fontColor(MUTED).width('100%')
        }
        Row({ space: 8 }) {
          Blank()
          ToolButton({ label: '取消', available: !this.busy, execute: () => { this.dialog = ''; } })
          Button(this.dialog === 'save' ? (this.busy ? '正在保存…' : '确认保存') : '放弃修改')
            .fontSize(13).height(36).backgroundColor(ACCENT).enabled(!this.busy)
            .onClick(() => {
              if (this.dialog === 'save') {
                this.save();
              } else {
                this.dialog = '';
                this.show(this.nextScreen);
              }
            })
        }
        .width('100%')
      }
      .width('90%').constraintSize({ maxWidth: 400 }).padding(18).backgroundColor(WHITE).borderRadius(8)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#85111634')
  }
}

@Component
struct ToolButton {
  @Prop label: string = '';
  @Prop available: boolean = false;
  execute: () => void = (): void => {};

  build() {
    Button(this.label, { type: ButtonType.Normal })
      .enabled(this.available).height(34).borderRadius(4).fontSize(12)
      .fontColor(this.available ? ACCENT : '#646D89').backgroundColor(this.available ? ACTIVE : '#EFF0F7')
      .padding({ left: 8, right: 8 }).onClick(() => this.execute())
  }
}