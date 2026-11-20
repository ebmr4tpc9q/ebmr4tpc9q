import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CATALOG, ItemType, MAX_ITEMS, PlacedItem, Plan, SURFACES, Surface, clonePlan, makeId, surfaceFor, typeFor } from '../domain/LayoutModel';
import { LayoutHistory } from '../domain/LayoutHistory';
import { LayoutIssue, inspectLayout, placeItem, transformed } from '../domain/LayoutRules';
import { PlanRepository, normalizeName } from '../data/PlanRepository';
import { PreferencesStore } from '../data/PreferencesStore';
import { PlanView } from './PlanView';

const INK: string = '#183531';
const MUTED: string = '#506860';
const PINE: string = '#10443D';
const LINE: string = '#D8E4D9';
const PAPER: string = '#F1F5ED';
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
        this.Navigation()
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
  Navigation() {
    Row({ space: 10 }) {
      Image($r('app.media.app_icon')).width(30).height(30).borderRadius(8)
      Text('角落计划').fontColor(INK).fontWeight(FontWeight.Bold).fontSize(21).layoutWeight(1)
      Button('首页', { type: ButtonType.Normal })
        .fontSize(13).height(36).borderRadius(10)
        .backgroundColor(this.screen === 'home' ? '#DBEBDD' : PAPER).fontColor(PINE)
        .onClick(() => this.go('home'))
      Button('方案库 ' + this.plans.length, { type: ButtonType.Normal })
        .fontSize(13).height(36).borderRadius(10)
        .backgroundColor(this.screen === 'library' ? PINE : '#DBEBDD')
        .fontColor(this.screen === 'library' ? WHITE : PINE)
        .onClick(() => this.go('library'))
    }
    .width('100%').height(58).padding({ left: 18, right: 18 })
  }

  @Builder
  Home() {
    Column({ space: 16 }) {
      Column({ space: 9 }) {
        Text('二维空间工作台').fontSize(30).fontWeight(FontWeight.Bold).fontColor('#F2F9EF')
        Text('选一张底图，把物件拖到合适的位置。')
          .fontSize(15).fontColor('#CDE7D6')
      }
      .width('100%').padding({ left: 20, right: 16, top: 24, bottom: 26 })
      .alignItems(HorizontalAlign.Start).borderRadius(20).backgroundColor(PINE)

      Text('选择底图').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      ForEach(SURFACES, (surface: Surface) => {
        Row({ space: 14 }) {
          Column() {
            PlanView({ plan: { id: surface.id, name: '', surface: surface.id, items: [] } })
          }
          .width(107).height(87).borderRadius(11).backgroundColor('#E9F0E7').hitTestBehavior(HitTestMode.None)
          Column({ space: 7 }) {
            Text(surface.label).fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK)
            Text(surface.description).fontSize(12).fontColor(MUTED)
            Text(surface.width + ' × ' + surface.height).fontSize(11).fontColor(MUTED)
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('›').fontSize(25).fontColor(PINE)
        }
        .height(112).width('100%').padding(12).backgroundColor(WHITE).borderRadius(15)
        .border({ width: 1, color: LINE })
        .onClick(() => this.edit(blankPlan(surface.id)))
      }, (surface: Surface) => surface.id)
      if (this.loadError !== '') {
        Text(this.loadError).fontSize(14).fontColor('#A44331').width('100%')
        Button('重试读取').backgroundColor(PINE).onClick(() => this.initialize()).enabled(!this.busy)
      }
    }
    .width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 18, right: 18, bottom: 18, top: 8 })
  }

  @Builder
  Editor() {
    Column({ space: 11 }) {
      Row({ space: 10 }) {
        Column({ space: 4 }) {
          Text(this.plan.name || '新建方案').fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(surfaceFor(this.plan.surface).label + '  ·  ' + this.plan.items.length + ' 件物件' +
            (this.dirty ? '  ·  有改动' : '')).fontSize(12).fontColor(MUTED)
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('保存方案', { type: ButtonType.Normal }).height(38).borderRadius(10).fontSize(14)
          .fontColor(WHITE).backgroundColor(PINE).enabled(!this.busy).onClick(() => this.prepareSave())
      }
      .width('100%')
      if (this.message !== '') {
        Text(this.message).fontSize(13).fontColor(PINE).padding(8).width('100%')
          .backgroundColor('#DBEBDD').borderRadius(8)
      }

      Column({ space: 6 }) {
        Row() {
          Text(this.layoutStatus()).fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor(this.issues.length === 0 ? PINE : '#A44331')
          Blank()
          Text('拖动布置').fontSize(12).fontColor(MUTED)
        }
        .width('100%').padding({ left: 12, right: 12, top: 10 })
        Column() {
          PlanView({
            plan: this.plan, selected: this.selected, interactive: true,
            onSelect: (id: string) => { this.selected = id; },
            onMove: (id: string, x: number, y: number) => this.move(id, x, y)
          })
        }
        .id('editor-canvas').width('100%').aspectRatio(1.30)
      }
      .width('100%').backgroundColor('#E5EEE5').borderRadius(15).border({ width: 1, color: LINE })

      Column({ space: 8 }) {
        Row({ space: 7 }) {
          Text(this.selectedSummary()).fontColor(INK).fontSize(13).fontWeight(FontWeight.Medium).layoutWeight(1)
          ToolButton({ label: '撤销', available: this.canUndo, execute: () => this.historyStep(true) })
          ToolButton({ label: '重做', available: this.canRedo, execute: () => this.historyStep(false) })
        }
        .width('100%')
        Row({ space: 6 }) {
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
      .width('100%').padding(10).backgroundColor(WHITE).borderRadius(13).border({ width: 1, color: LINE })

      Text('添加物件').width('100%').fontSize(17).fontColor(INK).fontWeight(FontWeight.Bold)
      Row({ space: 5 }) {
        ForEach(CATALOG, (type: ItemType) => {
          Column({ space: 5 }) {
            Row().width(19).height(9).backgroundColor(type.color).borderRadius(3)
            Text(type.label).fontSize(12).fontColor(INK).maxLines(1)
          }
          .layoutWeight(1).height(46).justifyContent(FlexAlign.Center).backgroundColor(WHITE)
          .borderRadius(8).border({ width: 1, color: LINE }).onClick(() => this.add(type))
        }, (type: ItemType) => type.id)
      }
      .width('100%')
    }
    .width('100%').constraintSize({ maxWidth: 600 }).padding({ left: 16, right: 16, top: 6, bottom: 18 })
  }


  @Builder
  Library() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 6 }) {
          Text('本地方案库').fontSize(26).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('点选方案可继续编辑  ·  ' + this.plans.length + ' / 30').fontSize(13).fontColor(MUTED)
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('新建空间').height(36).backgroundColor(PINE).fontSize(13).onClick(() => this.go('home'))
      }
      .width('100%').padding({ bottom: 4 })
      if (this.plans.length === 0) {
        Text(this.busy ? '正在读取方案…' : this.loadError || '还没有方案。新建空间并保存后，会出现在这里。')
          .fontSize(14).fontColor(MUTED).width('100%').padding(20).backgroundColor(WHITE).borderRadius(14)
      }
      ForEach(this.plans, (plan: Plan) => {
        Row({ space: 13 }) {
          Column() {
            PlanView({ plan: plan })
          }
          .width(104).height(80).backgroundColor('#E9F0E7').borderRadius(9).hitTestBehavior(HitTestMode.None)
          Column({ space: 6 }) {
            Text(plan.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(surfaceFor(plan.surface).label + '  ·  ' + plan.items.length + ' 件物件')
              .fontSize(12).fontColor(MUTED)
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('打开 ›').fontSize(13).fontColor(PINE)
        }
        .width('100%').padding(10).backgroundColor(WHITE).borderRadius(12).border({ width: 1, color: LINE })
        .onClick(() => this.edit(plan))
      }, (plan: Plan) => plan.id + JSON.stringify(plan))
    }
    .width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 18, right: 18, top: 14, bottom: 18 })
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
            Text('当前存在布局冲突，仍可保存草案。').fontSize(13).fontColor('#A44331').width('100%')
          }
          if (this.dialogError !== '') {
            Text(this.dialogError).fontSize(13).fontColor('#A44331').width('100%')
          }
        } else {
          Text('已保存的方案仍可在方案库中打开。').fontSize(14).fontColor(MUTED).width('100%')
        }
        Row({ space: 8 }) {
          Blank()
          ToolButton({ label: '取消', available: !this.busy, execute: () => { this.dialog = ''; } })
          Button(this.dialog === 'save' ? (this.busy ? '正在保存…' : '确认保存') : '放弃修改')
            .fontSize(13).height(36).backgroundColor(PINE).enabled(!this.busy)
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
      .width('90%').constraintSize({ maxWidth: 400 }).padding(18).backgroundColor(WHITE).borderRadius(18)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#70152B23')
  }
}

@Component
struct ToolButton {
  @Prop label: string = '';
  @Prop available: boolean = false;
  execute: () => void = (): void => {};

  build() {
    Button(this.label, { type: ButtonType.Normal })
      .enabled(this.available).height(34).borderRadius(7).fontSize(12)
      .fontColor(this.available ? PINE : '#687A71').backgroundColor(this.available ? '#DFEDE0' : '#EFF2ED')
      .padding({ left: 8, right: 8 }).onClick(() => this.execute())
  }
}