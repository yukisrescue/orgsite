import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const load = (name) => readFile(path.join(repo, name));
const text = async (name) => (await load(name)).toString('utf8');
const contract = JSON.parse(await text(
  'theme/yukis/tests/fixtures/vercel_contract.json',
));

test('frozen source assets have the reviewed digests', async () => {
  for (const [name, expected] of Object.entries(contract.assets)) {
    const actual = createHash('sha256').update(await load(name)).digest('hex');
    assert.equal(actual, expected, name);
  }
});

test('contract contains the complete one-page anchor and heading set', () => {
  assert.deepEqual(contract.anchors, [
    'top', 'about', 'mission', 'get-involved', 'contact',
  ]);
  assert.equal(contract.headings.length, 5);
});
