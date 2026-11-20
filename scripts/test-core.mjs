import assert from 'node:assert/strict';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = join(root, '.test-build');
const files = [
  'main/ets/domain/LayoutModel',
  'main/ets/domain/LayoutRules',
  'main/ets/domain/LayoutHistory',
  'main/ets/data/PlanRepository',
  'test/CoreCases'
];
const sources = await Promise.all(files.map(name => readFile(join(root, 'entry/src', name + '.ets'), 'utf8')));
const interfaces = new Set(sources.flatMap(source => [...source.matchAll(/export interface (\w+)/g)].map(match => match[1])));
for (const [index, name] of files.entries()) {
  const source = sources[index].replace(/import \{([^}]+)\} from '(\.[^']+)';/g, (_, names, path) => {
    const values = names.split(',').map(name => name.trim()).filter(name => !interfaces.has(name));
    return values.length ? `import { ${values.join(', ')} } from '${path}.mjs';` : '';
  });
  const esm = stripTypeScriptTypes(source);
  const target = join(output, name + '.mjs');
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, esm);
}
const { coreCases } = await import(pathToFileURL(join(output, 'test/CoreCases.mjs')));
const results = [];
for (const sample of coreCases()) {
  try {
    await sample.run();
    results.push({ id: sample.id, status: 'PASS' });
    console.log('PASS', sample.id);
  } catch (error) {
    results.push({ id: sample.id, status: 'FAIL', error: String(error) });
    console.error('FAIL', sample.id, error);
  }
}
await mkdir(join(root, 'evidence'), { recursive: true });
await writeFile(join(root, 'evidence/core-results.json'),
  JSON.stringify({ runtime: process.version, executedAt: new Date().toISOString(), tests: results }, null, 2) + '\n');
assert.ok(results.length >= 6 && results.every(test => test.status === 'PASS'));
