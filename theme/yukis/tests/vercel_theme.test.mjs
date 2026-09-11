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

test('prefixed front-page composition preserves source content', async () => {
  const front = await text('theme/yukis/templates/front-page.html');
  assert.match(front, /"slug":"vercel_header"/);
  assert.match(front, /wp:post-content/);
  assert.match(front, /"slug":"vercel_footer"/);

  const combined = [
    await text('theme/yukis/parts/vercel_header.html'),
    await text('theme/yukis/patterns/vercel_landing.php'),
    await text('theme/yukis/parts/vercel_footer.html'),
  ].join('\n');
  for (const anchor of contract.anchors) {
    assert.match(combined, new RegExp(`id="${anchor}"`));
  }
  for (const heading of contract.headings) assert.ok(combined.includes(heading));
  for (const phrase of [
    "placeholder copy — replace with the organization's real story.",
    'Rescue', 'Rehabilitation', 'Rehoming',
    'Adopt', 'Volunteer', 'Donate',
    '1221 Coral Reef Place, Alameda, CA',
    '510.350.6924', '41-4413466',
  ]) assert.ok(combined.includes(phrase), phrase);
  const classes = [...combined.matchAll(/class="([^"]+)"/g)]
    .flatMap((match) => match[1].split(/\s+/));
  const unexpected = classes.filter((name) => ![
    'vercel_', 'wp-', 'has-', 'is-', 'align', 'size-',
  ].some((prefix) => name.startsWith(prefix)));
  assert.deepEqual(unexpected, []);
});
