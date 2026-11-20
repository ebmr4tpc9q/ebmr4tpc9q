import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as wait } from 'node:timers/promises';

const root = fileURLToPath(new URL('../', import.meta.url));
const hdc = process.env.CORNER_HDC || 'hdc';
const device = process.env.CORNER_DEVICE || '127.0.0.1:5555';
const bundle = 'com.coursework.cornerplan';
const runId = Date.now().toString(36);
const out = resolve(root, 'evidence');
const screenshots = resolve(out, 'screenshots');
mkdirSync(screenshots, { recursive: true });
let sequence = 0;
const results = [];

function run(...args) {
  const result = spawnSync(hdc, ['-t', device, ...args], {
    encoding: 'utf8', timeout: 14000, windowsHide: true, maxBuffer: 5 * 1024 * 1024
  });
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
  return result.stdout.trim();
}

function shell(command) {
  return run('shell', command);
}

async function layout() {
  const remote = '/data/local/tmp/corner-layout-' + runId + '.json';
  const reply = shell('uitest dumpLayout -b ' + bundle + ' -p ' + remote + '; cat ' + remote);
  const first = reply.indexOf('{');
  assert.ok(first >= 0, 'No visible CornerPlan UI: ' + reply.slice(0, 180));
  const tree = JSON.parse(reply.slice(first));
  function flatten(node) {
    return [node.attributes, ...(node.children || []).flatMap(flatten)];
  }
  return flatten(tree).filter(Boolean);
}

const has = (node, label) => typeof label === 'string' ? node.text === label : label.test(node.text || '');

async function visible(label) {
  for (let i = 0; i < 4; i++) {
    const nodes = await layout();
    if (nodes.some(node => has(node, label))) return nodes;
    await wait(220);
  }
  const nodes = await layout();
  assert.fail('Missing ' + label + ': ' + nodes.map(node => node.text).filter(Boolean).join(' | '));
}

function bounds(node) {
  const coords = node?.bounds?.match(/-?\d+/g)?.map(Number);
  assert.equal(coords?.length, 4, 'No bounds for ' + JSON.stringify(node));
  return coords;
}

function center(node) {
  const [x1, y1, x2, y2] = bounds(node);
  return [Math.round((x1 + x2) / 2), Math.round((y1 + y2) / 2)];
}

async function tap(label) {
  const nodes = await visible(label);
  const [x, y] = center(nodes.find(node => has(node, label)));
  shell('uitest uiInput click ' + x + ' ' + y);
  await wait(420);
}

async function shot(name) {
  const remote = '/data/local/tmp/corner-' + runId + '-' + sequence++ + '.png';
  const actual = shell('uitest screenCap -p ' + remote);
  assert.ok(actual.includes('saved'), actual);
  run('file', 'recv', remote, resolve(screenshots, name + '.png'));
  shell('rm ' + remote);
}

async function canvasPoint(x, y, width = 480, height = 360) {
  const nodes = await visible('拖动布置');
  const canvas = nodes.find(node => node.key === 'editor-canvas' || node.id === 'editor-canvas') ||
    nodes.find(node => node.type === 'Canvas');
  const [x1, y1, x2, y2] = bounds(canvas);
  const deviceScale = Number(process.env.CORNER_DENSITY || 3.5);
  const inset = 15 * deviceScale;
  const scale = Math.min((x2 - x1 - 2 * inset) / width, (y2 - y1 - 2 * inset) / height);
  return [
    Math.round((x1 + x2) / 2 + (x - width / 2) * scale),
    Math.round((y1 + y2) / 2 + (y - height / 2) * scale)
  ];
}

async function drag(x, y, targetX, targetY) {
  const start = await canvasPoint(x, y);
  const end = await canvasPoint(targetX, targetY);
  shell('uitest uiInput drag ' + [...start, ...end, 700].join(' '));
  await wait(420);
}

async function canvasTap(x, y) {
  const point = await canvasPoint(x, y);
  shell('uitest uiInput click ' + point.join(' '));
  await wait(420);
}

async function save(name, typeName = true) {
  await tap('保存方案');
  if (typeName) {
    const nodes = await visible('确认保存');
    const field = nodes.find(node => node.key === 'plan-name' || node.id === 'plan-name' || node.type === 'TextInput');
    const [x, y] = center(field);
    shell('uitest uiInput inputText ' + x + ' ' + y + ' ' + name);
    await wait(550);
  }
  await tap('确认保存');
  await visible('已保存「' + name + '」');
}

async function step(id, operation) {
  const started = Date.now();
  const detail = await operation();
  results.push({ id, status: 'PASS', durationMs: Date.now() - started, detail: detail || '' });
  console.log('PASS', id);
  await wait(550);
}

let failure;
try {
  assert.match(shell('aa start -a EntryAbility -b ' + bundle), /successfully/);
  await wait(1100);
  await step('U01 two native templates, blank library', async () => {
    await visible('方案库 0');
    await visible('双人宿舍');
    await visible('社团展位');
    await shot('01-templates');
    await tap('双人宿舍');
    await visible('双人宿舍  ·  0 件物件');
  });
  await step('U02 drag, overlap, boundary, undo and redo', async () => {
    await tap('床');
    await tap('书桌');
    await drag(228, 48, 96, 56);
    await visible('越界 0 件  ·  重叠 1 组');
    await shot('02-overlap');
    await tap('撤销');
    await visible('布局无冲突');
    await tap('重做');
    await visible('越界 0 件  ·  重叠 1 组');
    await tap('撤销');
    await drag(96, 56, 4, 80);
    await visible('越界 1 件  ·  重叠 0 组');
    await shot('03-boundary');
    await tap('撤销');
    await visible('布局无冲突');
    await drag(96, 56, 114, 209);
    await visible('布局无冲突');
  });
  await step('U03 six items, tap selection, transform, delete and undo', async () => {
    for (const item of ['收纳柜', '椅子', '展台', '展板']) await tap(item);
    await visible(/6 件物件/);
    await canvasTap(114, 209);
    await visible(/床.*0°.*1\.0×/);
    await tap('转 +15°');
    await tap('放大');
    await visible(/床.*15°.*1\.1×/);
    await tap('删除');
    await visible(/5 件物件/);
    await tap('撤销');
    await visible(/6 件物件/);
    await canvasTap(114, 209);
    await visible(/床.*15°.*1\.1×/);
    await shot('04-editor');
  });
  await step('U04 blank name validation and first save', async () => {
    await tap('保存方案');
    await tap('确认保存');
    await visible('请输入 1～24 个字符的方案名称');
    await tap('取消');
    await save('Dorm-Day');
    await tap('首页');
  });
  await step('U05 save a booth and a second dorm', async () => {
    await tap('社团展位');
    await visible('社团展位  ·  0 件物件');
    await tap('展台');
    await tap('展板');
    await save('Expo-Open');
    await tap('首页');
    await tap('双人宿舍');
    await tap('椅子');
    await save('Dorm-Quiet');
    await tap('方案库 3');
    for (const name of ['Dorm-Day', 'Expo-Open', 'Dorm-Quiet']) await visible(name);
    await shot('05-library-before');
    await tap('Dorm-Day');
    await canvasTap(114, 209);
    await visible(/床.*15°.*1\.1×/);
    await shot('06-editor-before');
    await tap('方案库 3');
  });
  await step('U06 actual process termination, reload, reopen and update', async () => {
    const before = shell('pidof ' + bundle);
    assert.match(before, /^\d+$/);
    shell('aa force-stop ' + bundle);
    await wait(900);
    assert.equal(shell('pidof ' + bundle), '', 'Process still running after force-stop');
    assert.match(shell('aa start -a EntryAbility -b ' + bundle), /successfully/);
    await wait(1100);
    const after = shell('pidof ' + bundle);
    assert.match(after, /^\d+$/);
    assert.notEqual(before, after, 'Process ID unchanged after relaunch');
    await tap('方案库 3');
    for (const name of ['Dorm-Day', 'Expo-Open', 'Dorm-Quiet']) await visible(name);
    await shot('07-library-after');
    await tap('Dorm-Day');
    await canvasTap(114, 209);
    await visible(/床.*15°.*1\.1×/);
    await shot('08-editor-after');
    await tap('转 +15°');
    await visible(/床.*30°.*1\.1×/);
    await save('Dorm-Day', false);
    await visible('方案库 3');
    await shot('09-update-after-restart');
    return { beforePid: Number(before), afterPid: Number(after), plansRestored: 3, continuedRotation: 30 };
  });
} catch (error) {
  failure = error;
  console.error(error);
  try { await shot('failure'); } catch {}
} finally {
  writeFileSync(resolve(out, 'native-results.json'), JSON.stringify({
    executedAt: new Date().toISOString(), target: device, system: shell('param get const.product.software.version'),
    tests: results, status: failure ? 'FAIL' : 'PASS', error: failure ? String(failure) : undefined
  }, null, 2) + '\n');
}
if (failure) process.exitCode = 1;
