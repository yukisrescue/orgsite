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

test('theme registers the Vercel palette, fonts, and template parts', async () => {
  const theme = JSON.parse(await text('theme/yukis/theme.json'));
  const palette = Object.fromEntries(
    theme.settings.color.palette.map(({ slug, color }) => [slug, color]),
  );
  for (const [slug, color] of Object.entries(contract.colors)) {
    assert.equal(palette[slug], color, slug);
  }
  const families = theme.settings.typography.fontFamilies;
  assert.deepEqual(families.map(({ slug }) => slug), [
    'system', 'vercel_inter', 'vercel_fraunces',
  ]);
  assert.deepEqual(theme.templateParts.map(({ name }) => name), [
    'header', 'footer', 'vercel_header', 'vercel_footer',
  ]);
});

test('front-page assets and metadata are registered with prefixed names', async () => {
  const php = await text('theme/yukis/functions.php');
  for (const token of [
    'vercel_enqueue_assets',
    "'vercel_styles'",
    "'vercel_reveal'",
    'vercel_render_metadata',
    'vercel_document_title',
    'application/ld+json',
    'Yuki&#039;s Rescue | Alameda, CA',
  ]) assert.ok(php.includes(token), token);
});
