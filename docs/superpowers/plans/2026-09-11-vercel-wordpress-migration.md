# Vercel Landing Page WordPress Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or `superpowers:executing-plans` to
> implement this plan task-by-task. This repository forbids Markdown task
> checklists; FP child issues track state, and the steps below are numbered.

**Goal:** Reproduce the 2026-09-11 Vercel landing page faithfully as the
editable WordPress front page and publish a self-contained static export.

**Architecture:** Extend the existing `theme/yukis` block theme with prefixed
template parts, a reusable landing-page pattern, local assets, metadata, and a
small progressive-enhancement script. Seed the registered pattern into the
existing Home page, verify the export while the publisher is stopped, then use
the existing Git and Cloudflare deployment path.

**Tech Stack:** WordPress block themes and WP-CLI, PHP, HTML/CSS, browser-native
JavaScript, Node.js built-in tests, Bash, Simply Static, Git, Cloudflare Workers.

**Issue:** `YUKI-ndkaskno`

**Spec:** `docs/superpowers/specs/2026-09-11-vercel-wordpress-migration-design.md`

---

## Global Constraints

- Work only in the `codex/vercel-wordpress-migration` worktree until the final
  integration decision.
- Preserve the Vercel page's current text, including explicit placeholder text.
- Every migration-specific identifier begins with `vercel_`. WordPress-reserved
  entrypoint names such as `templates/front-page.html` are the only exception.
- Do not add React, Next.js, Tailwind, a page builder, or a remote font/runtime
  dependency.
- Do not modify or delete the Vercel deployment, the contact Worker, or the
  existing `/about/`, `/rescue/`, and `/feedback/` WordPress pages.
- Stop `yukis-publisher` before generating the first migrated export. A local
  visual review must happen before production deployment.
- Run `drift refs <path>` before editing a bound file and `drift check` before
  each documentation or integration commit.
- Mention `YUKI-ndkaskno` in every implementation commit.

## File Map

| Path | Responsibility |
|---|---|
| `package.json` | Local migration-contract test command |
| `theme/yukis/tests/fixtures/vercel_contract.json` | Frozen source values and asset digests |
| `theme/yukis/tests/vercel_theme.test.mjs` | Theme, naming, content, metadata, and asset contract |
| `theme/yukis/assets/images/vercel_logo.png` | Source logo, 431 by 485 pixels |
| `theme/yukis/assets/images/vercel_hero.svg` | Source social-sharing background |
| `theme/yukis/assets/fonts/vercel_inter.woff2` | Local Inter variable Latin font |
| `theme/yukis/assets/fonts/vercel_fraunces.woff2` | Local Fraunces normal Latin font |
| `theme/yukis/assets/fonts/vercel_fraunces_italic.woff2` | Local Fraunces italic Latin font |
| `theme/yukis/style.css` | Theme metadata and cache-busting version |
| `theme/yukis/theme.json` | Vercel palette, typography, and registered template parts |
| `theme/yukis/functions.php` | Asset loading and front-page metadata |
| `theme/yukis/assets/css/vercel_styles.css` | Faithful responsive presentation |
| `theme/yukis/assets/js/vercel_reveal.js` | Optional reveal enhancement |
| `theme/yukis/parts/vercel_header.html` | Vercel-only front-page header |
| `theme/yukis/parts/vercel_footer.html` | Vercel-only front-page footer |
| `theme/yukis/patterns/vercel_landing.php` | Canonical editable landing-page blocks |
| `theme/yukis/templates/front-page.html` | WordPress entrypoint composing prefixed parts |
| `deploy/wordpress/vercel_migrate_home.sh` | Guarded one-time update of the existing Home page |
| `deploy/wordpress/tests/test-vercel-migrate.sh` | Migration-script guard and update tests |
| `deploy/wordpress/wp-content-seed.sh` | Fresh-install Home creation through the Vercel pattern |
| `deploy/wordpress/seed/home.html` | Removed obsolete pre-Vercel Home seed |
| `deploy/wordpress/ss-configure.php` | Explicit export URLs for new theme assets |
| `deploy/wordpress/publish.sh` | Missing nested CSS-asset protection |
| `deploy/wordpress/tests/test-publish.sh` | Regression test for a missing font referenced by CSS |
| `docs/DESIGNERS.md` | Explain the new one-page structure and anchor navigation |

## Task 1: Freeze the source contract and assets

**FP child:** `YUKI-zeygqdyt`

**Files:**

- Modify: `package.json`
- Create: `theme/yukis/tests/fixtures/vercel_contract.json`
- Create: `theme/yukis/tests/vercel_theme.test.mjs`
- Create: the five files below `theme/yukis/assets/{images,fonts}/`

### Step 1: Add the contract test command

Add this script to the existing `scripts` object in `package.json`:

```json
"test:vercel": "node --test theme/yukis/tests/vercel_theme.test.mjs"
```

### Step 2: Add the frozen contract fixture

Create `theme/yukis/tests/fixtures/vercel_contract.json`:

```json
{
  "source": "https://yukis-rescue-org.vercel.app/",
  "observed": "2026-09-11",
  "colors": {
    "vercel_background": "#faf8f4",
    "vercel_foreground": "#2b2a28",
    "vercel_muted": "#f1ece2",
    "vercel_muted_foreground": "#6b6459",
    "vercel_border": "#e4ddd0",
    "vercel_accent": "#8a7998",
    "vercel_sage": "#7e8c72",
    "vercel_white": "#ffffff"
  },
  "anchors": ["top", "about", "mission", "get-involved", "contact"],
  "headings": [
    "Second chances for dogs, one home at a time.",
    "Who we are",
    "What guides our work",
    "Ways to help",
    "We’d love to hear from you"
  ],
  "assets": {
    "theme/yukis/assets/images/vercel_logo.png": "a9031257fa81cdb416d87dcae7c36227302f42272b0de22d5624ecc6078d60ef",
    "theme/yukis/assets/images/vercel_hero.svg": "6c3cf7d09fd568a6c84cf7bad42227436ddec90d62efcacbca124a0559a0b446",
    "theme/yukis/assets/fonts/vercel_fraunces.woff2": "88e17be075f1be50ab67b057b99e3701b828f44ed28f9452df6c02645bb0cba9",
    "theme/yukis/assets/fonts/vercel_fraunces_italic.woff2": "c9745ee907c02cdd46cc41a65bb711cd861432f679a76c18e3de204a18723040",
    "theme/yukis/assets/fonts/vercel_inter.woff2": "c940764593d0fe5d596be327ca7558855e018039fb78509aa21921fd3644c3e4"
  }
}
```

### Step 3: Write the initial asset and contract test

Create `theme/yukis/tests/vercel_theme.test.mjs`:

```js
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
```

### Step 4: Download the exact reviewed assets

```bash
mkdir -p theme/yukis/assets/images theme/yukis/assets/fonts
curl -fsSL https://yukis-rescue-org.vercel.app/assets/logo.png \
  -o theme/yukis/assets/images/vercel_logo.png
curl -fsSL https://yukis-rescue-org.vercel.app/assets/hero.svg \
  -o theme/yukis/assets/images/vercel_hero.svg
curl -fsSL https://yukis-rescue-org.vercel.app/_next/static/media/03bda585a99c6450-s.p.32sris142tqlb.woff2 \
  -o theme/yukis/assets/fonts/vercel_fraunces.woff2
curl -fsSL https://yukis-rescue-org.vercel.app/_next/static/media/3c7c6164b2587822-s.p.16u3vygyjnhr0.woff2 \
  -o theme/yukis/assets/fonts/vercel_fraunces_italic.woff2
curl -fsSL https://yukis-rescue-org.vercel.app/_next/static/media/83afe278b6a6bb3c-s.p.2bn3s6zvc0dyp.woff2 \
  -o theme/yukis/assets/fonts/vercel_inter.woff2
```

### Step 5: Verify and commit the source snapshot

Run:

```bash
npm run test:vercel
```

Expected: two tests pass. Then commit:

```bash
git add package.json theme/yukis/assets theme/yukis/tests
git commit -m "test: freeze Vercel source contract (YUKI-ndkaskno)"
```

## Task 2: Register Vercel tokens, fonts, assets, and metadata

**Depends on:** Task 1

**FP child:** `YUKI-taqplpol`

**Files:**

- Modify: `theme/yukis/tests/vercel_theme.test.mjs`
- Modify: `theme/yukis/style.css`
- Modify: `theme/yukis/theme.json`
- Create: `theme/yukis/functions.php`

### Step 1: Add failing token and loader tests

Append to `vercel_theme.test.mjs`:

```js
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
    'vercel_inter', 'vercel_fraunces',
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
  ]) assert.match(php, new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
});
```

Run `npm run test:vercel`. Expected: failure because the old palette and missing
`functions.php` do not satisfy the Vercel contract.

### Step 2: Extend the theme token set without changing legacy tokens

Update `theme/yukis/theme.json` while preserving the existing schema,
appearance tools, 1200-pixel layout, six legacy palette entries, global body
styles, and legacy `header`/`footer` registrations. Append the Vercel palette
and fonts so `/about/`, `/rescue/`, and `/feedback/` retain their current token
values. Append these objects to `settings.color.palette`:

```json
[
    { "slug": "vercel_background", "color": "#faf8f4", "name": "Vercel Background" },
    { "slug": "vercel_foreground", "color": "#2b2a28", "name": "Vercel Foreground" },
    { "slug": "vercel_muted", "color": "#f1ece2", "name": "Vercel Muted" },
    { "slug": "vercel_muted_foreground", "color": "#6b6459", "name": "Vercel Muted Foreground" },
    { "slug": "vercel_border", "color": "#e4ddd0", "name": "Vercel Border" },
    { "slug": "vercel_accent", "color": "#8a7998", "name": "Vercel Accent" },
    { "slug": "vercel_sage", "color": "#7e8c72", "name": "Vercel Sage" },
    { "slug": "vercel_white", "color": "#ffffff", "name": "Vercel White" }
]
```

Replace `settings.typography.fontFamilies` with:

```json
[
    {
      "slug": "vercel_inter",
      "name": "Inter",
      "fontFamily": "Inter, Arial, sans-serif",
      "fontFace": [{
        "fontFamily": "Inter",
        "fontStyle": "normal",
        "fontWeight": "300 600",
        "src": ["file:./assets/fonts/vercel_inter.woff2"]
      }]
    },
    {
      "slug": "vercel_fraunces",
      "name": "Fraunces",
      "fontFamily": "Fraunces, Georgia, serif",
      "fontFace": [
        {
          "fontFamily": "Fraunces",
          "fontStyle": "normal",
          "fontWeight": "400 600",
          "src": ["file:./assets/fonts/vercel_fraunces.woff2"]
        },
        {
          "fontFamily": "Fraunces",
          "fontStyle": "italic",
          "fontWeight": "400 600",
          "src": ["file:./assets/fonts/vercel_fraunces_italic.woff2"]
        }
      ]
    }
]
```

Do not change the global body text or system font; the front-page stylesheet is
scoped to `.vercel_main`. Register these parts after the existing parts:

```json
{ "name": "vercel_header", "title": "Vercel Header", "area": "header" },
{ "name": "vercel_footer", "title": "Vercel Footer", "area": "footer" }
```

### Step 3: Add the theme loader and front-page metadata

Change the version in `theme/yukis/style.css` from `1.0.0` to `1.1.0` so the
new stylesheet and script receive a new cache key.

Create `theme/yukis/functions.php`:

```php
<?php
function vercel_enqueue_assets(): void {
    if (!is_front_page()) { return; }
    $version = wp_get_theme()->get('Version');
    wp_enqueue_style(
        'vercel_styles',
        get_theme_file_uri('assets/css/vercel_styles.css'),
        [],
        $version
    );
    wp_enqueue_script(
        'vercel_reveal',
        get_theme_file_uri('assets/js/vercel_reveal.js'),
        [],
        $version,
        ['strategy' => 'defer', 'in_footer' => true]
    );
}
add_action('wp_enqueue_scripts', 'vercel_enqueue_assets');

function vercel_enqueue_editor_assets(): void {
    wp_enqueue_style(
        'vercel_styles',
        get_theme_file_uri('assets/css/vercel_styles.css'),
        [],
        wp_get_theme()->get('Version')
    );
}
add_action('enqueue_block_editor_assets', 'vercel_enqueue_editor_assets');

function vercel_render_metadata(): void {
    if (!is_front_page()) { return; }
    $description = "Second chances for dogs, one home at a time. Yuki's Rescue is a 501(c)(3) dog rescue in Alameda, CA.";
    $image = get_theme_file_uri('assets/images/vercel_hero.svg');
    $schema = [
        '@context' => 'https://schema.org',
        '@type' => 'NGO',
        'name' => "Yuki's Rescue",
        'description' => 'Second chances for dogs, one home at a time.',
        'telephone' => '510.350.6924',
        'foundingDate' => '2026',
        'taxID' => '41-4413466',
        'address' => [
            '@type' => 'PostalAddress',
            'streetAddress' => '1221 Coral Reef Place',
            'addressLocality' => 'Alameda',
            'addressRegion' => 'CA',
            'addressCountry' => 'US',
        ],
    ];
    echo '<meta name="description" content="' . esc_attr($description) . '">' . "\n";
    echo '<meta property="og:title" content="Yuki&#039;s Rescue | Alameda, CA">' . "\n";
    echo '<meta property="og:description" content="' . esc_attr($description) . '">' . "\n";
    echo '<meta property="og:image" content="' . esc_url($image) . '">' . "\n";
    echo '<meta property="og:image:alt" content="Placeholder hero image — replace with a real photo of a Yuki&#039;s Rescue dog">' . "\n";
    echo '<meta property="og:type" content="website">' . "\n";
    echo '<meta name="twitter:card" content="summary_large_image">' . "\n";
    echo '<meta name="twitter:title" content="Yuki&#039;s Rescue | Alameda, CA">' . "\n";
    echo '<meta name="twitter:description" content="' . esc_attr($description) . '">' . "\n";
    echo '<meta name="twitter:image" content="' . esc_url($image) . '">' . "\n";
    echo '<meta name="twitter:image:alt" content="Placeholder hero image — replace with a real photo of a Yuki&#039;s Rescue dog">' . "\n";
    echo '<script type="application/ld+json">' . wp_json_encode($schema, JSON_UNESCAPED_SLASHES) . '</script>' . "\n";
}
add_action('wp_head', 'vercel_render_metadata', 5);

function vercel_document_title(string $title): string {
    return is_front_page() ? "Yuki's Rescue | Alameda, CA" : $title;
}
add_filter('pre_get_document_title', 'vercel_document_title');
```

### Step 4: Run the tests and commit

Run `npm run test:vercel`. Expected: four tests pass. Commit:

```bash
git add theme/yukis/style.css theme/yukis/theme.json theme/yukis/functions.php \
  theme/yukis/tests
git commit -m "feat: register Vercel theme foundation (YUKI-ndkaskno)"
```

## Task 3: Build the prefixed WordPress template and content blocks

**Depends on:** Task 2

**FP child:** `YUKI-bioydkqc`

**Files:**

- Modify: `theme/yukis/tests/vercel_theme.test.mjs`
- Modify: `theme/yukis/templates/front-page.html`
- Create: `theme/yukis/parts/vercel_header.html`
- Create: `theme/yukis/parts/vercel_footer.html`
- Create: `theme/yukis/patterns/vercel_landing.php`

### Step 1: Add failing structural and content assertions

Append a test that reads the four files and asserts:

```js
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
    'vercel_', 'wp-', 'has-', 'is-', 'align', 'size-'
  ].some((prefix) => name.startsWith(prefix)));
  assert.deepEqual(unexpected, []);
});
```

Run `npm run test:vercel`. Expected: failure because the prefixed parts and
pattern do not exist.

### Step 2: Create the front-page composition

Replace `theme/yukis/templates/front-page.html` with:

```html
<!-- wp:template-part {"slug":"vercel_header","tagName":"header"} /-->
<!-- wp:post-content {"tagName":"main","className":"vercel_main","layout":{"type":"default"}} /-->
<!-- wp:template-part {"slug":"vercel_footer","tagName":"footer"} /-->
```

### Step 3: Create the header and footer parts

Create `theme/yukis/parts/vercel_header.html`:

```html
<!-- wp:group {"className":"vercel_header","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_header"><!-- wp:group {"className":"vercel_header_inner","layout":{"type":"flex","flexWrap":"nowrap","justifyContent":"space-between"}} -->
<div class="wp-block-group vercel_header_inner"><!-- wp:group {"className":"vercel_header_brand","layout":{"type":"flex","flexWrap":"nowrap"}} -->
<div class="wp-block-group vercel_header_brand"><!-- wp:image {"width":"44px","sizeSlug":"full","linkDestination":"custom","className":"vercel_header_logo"} -->
<figure class="wp-block-image size-full is-resized vercel_header_logo"><a href="#top"><img src="/wp-content/themes/yukis/assets/images/vercel_logo.png" alt="Yuki's Rescue logo — a dog portrait framed by ferns and flowers, Alameda, Est. 2026" style="width:44px"/></a></figure>
<!-- /wp:image --><!-- wp:paragraph {"className":"vercel_header_name"} -->
<p class="vercel_header_name"><a href="#top">Yuki's Rescue</a></p>
<!-- /wp:paragraph --></div>
<!-- /wp:group --><!-- wp:navigation {"overlayMenu":"never","className":"vercel_header_nav","layout":{"type":"flex","justifyContent":"right","flexWrap":"nowrap"}} -->
<!-- wp:navigation-link {"label":"About","url":"#about","kind":"custom"} /-->
<!-- wp:navigation-link {"label":"Mission","url":"#mission","kind":"custom"} /-->
<!-- wp:navigation-link {"label":"Get Involved","url":"#get-involved","kind":"custom"} /-->
<!-- wp:navigation-link {"label":"Contact","url":"#contact","kind":"custom"} /-->
<!-- /wp:navigation --></div>
<!-- /wp:group --></div>
<!-- /wp:group -->
```

Create `theme/yukis/parts/vercel_footer.html`:

```html
<!-- wp:group {"className":"vercel_footer","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_footer"><!-- wp:group {"className":"vercel_footer_inner","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_footer_inner"><!-- wp:group {"className":"vercel_footer_top","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_footer_top"><!-- wp:group {"className":"vercel_footer_address","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_footer_address"><!-- wp:paragraph {"className":"vercel_footer_identity"} -->
<p class="vercel_footer_identity">Yuki's Rescue</p>
<!-- /wp:paragraph --><!-- wp:paragraph -->
<p>1221 Coral Reef Place, Alameda, CA</p>
<!-- /wp:paragraph --><!-- wp:paragraph -->
<p><a href="tel:5103506924">510.350.6924</a></p>
<!-- /wp:paragraph --></div>
<!-- /wp:group --></div>
<!-- /wp:group --><!-- wp:group {"className":"vercel_footer_legal","layout":{"type":"flex","flexWrap":"wrap","justifyContent":"space-between"}} -->
<div class="wp-block-group vercel_footer_legal"><!-- wp:paragraph -->
<p>Yuki's Rescue is a registered 501(c)(3) nonprofit organization. EIN #41-4413466.</p>
<!-- /wp:paragraph --><!-- wp:paragraph -->
<p>© 2026 Yuki's Rescue. All rights reserved.</p>
<!-- /wp:paragraph --></div>
<!-- /wp:group --></div>
<!-- /wp:group --></div>
<!-- /wp:group -->
```

### Step 4: Create the landing pattern with exact copy

Create `theme/yukis/patterns/vercel_landing.php` with pattern headers:

```php
<?php
/**
 * Title: Vercel Landing Page
 * Slug: yukis/vercel_landing
 * Categories: featured
 * Inserter: true
 */
?>
```

After the PHP header, add this block markup:

```html
<!-- wp:group {"anchor":"top","className":"vercel_section vercel_hero","layout":{"type":"default"}} -->
<div id="top" class="wp-block-group vercel_section vercel_hero"><!-- wp:group {"className":"vercel_section_inner","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_section_inner"><!-- wp:columns {"className":"vercel_hero_grid"} -->
<div class="wp-block-columns vercel_hero_grid"><!-- wp:column {"className":"vercel_hero_copy"} -->
<div class="wp-block-column vercel_hero_copy"><!-- wp:paragraph {"className":"vercel_eyebrow"} -->
<p class="vercel_eyebrow">Alameda, CA · Est. 2026</p>
<!-- /wp:paragraph --><!-- wp:heading {"level":1} -->
<h1 class="wp-block-heading">Second chances for dogs, one home at a time.</h1>
<!-- /wp:heading --><!-- wp:paragraph {"className":"vercel_lead"} -->
<p class="vercel_lead">Yuki's Rescue is a volunteer-run dog rescue dedicated to rescue, rehabilitation, and rehoming — placeholder copy, refine with the real mission statement.</p>
<!-- /wp:paragraph --><!-- wp:group {"className":"vercel_buttons","layout":{"type":"flex","flexWrap":"wrap"}} -->
<div class="wp-block-group vercel_buttons"><!-- wp:button {"className":"vercel_button"} -->
<div class="wp-block-button vercel_button"><a class="wp-block-button__link wp-element-button" href="#get-involved">See how you can help</a></div>
<!-- /wp:button --><!-- wp:paragraph {"className":"vercel_text_link"} -->
<p class="vercel_text_link"><a href="#about">Our story</a></p>
<!-- /wp:paragraph --></div>
<!-- /wp:group --></div>
<!-- /wp:column --><!-- wp:column {"className":"vercel_hero_art"} -->
<div class="wp-block-column vercel_hero_art"><!-- wp:image {"sizeSlug":"full","linkDestination":"none"} -->
<figure class="wp-block-image size-full"><img src="/wp-content/themes/yukis/assets/images/vercel_logo.png" alt="Yuki's Rescue logo — a dog portrait framed by ferns and flowers, Alameda, Est. 2026"/></figure>
<!-- /wp:image --></div>
<!-- /wp:column --></div>
<!-- /wp:columns --></div>
<!-- /wp:group --></div>
<!-- /wp:group -->

<!-- wp:group {"anchor":"about","className":"vercel_section vercel_section_muted vercel_reveal","layout":{"type":"default"}} -->
<div id="about" class="wp-block-group vercel_section vercel_section_muted vercel_reveal"><!-- wp:group {"className":"vercel_section_inner vercel_about_inner","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_section_inner vercel_about_inner"><!-- wp:paragraph {"className":"vercel_eyebrow"} -->
<p class="vercel_eyebrow">About</p>
<!-- /wp:paragraph --><!-- wp:heading -->
<h2 class="wp-block-heading">Who we are</h2>
<!-- /wp:heading --><!-- wp:paragraph {"className":"vercel_about_text"} -->
<p class="vercel_about_text">Yuki's Rescue is a small, volunteer-run dog rescue based in Alameda, California. We step in for dogs in crowded shelters and difficult situations, support them through veterinary care and rehabilitation, and find them loving, permanent homes. This is placeholder copy — replace with the organization's real story.</p>
<!-- /wp:paragraph --></div>
<!-- /wp:group --></div>
<!-- /wp:group -->

<!-- wp:group {"anchor":"mission","className":"vercel_section vercel_reveal","layout":{"type":"default"}} -->
<div id="mission" class="wp-block-group vercel_section vercel_reveal"><!-- wp:group {"className":"vercel_section_inner","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_section_inner"><!-- wp:paragraph {"className":"vercel_eyebrow"} -->
<p class="vercel_eyebrow">Mission</p>
<!-- /wp:paragraph --><!-- wp:heading -->
<h2 class="wp-block-heading">What guides our work</h2>
<!-- /wp:heading --><!-- wp:columns {"className":"vercel_mission_grid"} -->
<div class="wp-block-columns vercel_mission_grid"><!-- wp:column {"className":"vercel_mission_item"} -->
<div class="wp-block-column vercel_mission_item"><!-- wp:html --><span class="vercel_icon vercel_icon_rescue" aria-hidden="true"></span><!-- /wp:html --><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Rescue</h3><!-- /wp:heading --><!-- wp:paragraph --><p>We step in for dogs in crisis — from overcrowded shelters, surrenders, and the street — giving each one a safe place to land.</p><!-- /wp:paragraph --></div>
<!-- /wp:column --><!-- wp:column {"className":"vercel_mission_item"} -->
<div class="wp-block-column vercel_mission_item"><!-- wp:html --><span class="vercel_icon vercel_icon_rehabilitation" aria-hidden="true"></span><!-- /wp:html --><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Rehabilitation</h3><!-- /wp:heading --><!-- wp:paragraph --><p>Every dog in our care receives veterinary treatment and patient behavioral support for as long as healing takes.</p><!-- /wp:paragraph --></div>
<!-- /wp:column --><!-- wp:column {"className":"vercel_mission_item"} -->
<div class="wp-block-column vercel_mission_item"><!-- wp:html --><span class="vercel_icon vercel_icon_rehoming" aria-hidden="true"></span><!-- /wp:html --><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Rehoming</h3><!-- /wp:heading --><!-- wp:paragraph --><p>We take matching seriously — every adopter is screened and supported, so each placement is built to last.</p><!-- /wp:paragraph --></div>
<!-- /wp:column --></div>
<!-- /wp:columns --></div>
<!-- /wp:group --></div>
<!-- /wp:group -->

<!-- wp:group {"anchor":"get-involved","className":"vercel_section vercel_section_muted vercel_reveal","layout":{"type":"default"}} -->
<div id="get-involved" class="wp-block-group vercel_section vercel_section_muted vercel_reveal"><!-- wp:group {"className":"vercel_section_inner","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_section_inner"><!-- wp:paragraph {"className":"vercel_eyebrow"} --><p class="vercel_eyebrow">Get Involved</p><!-- /wp:paragraph --><!-- wp:heading --><h2 class="wp-block-heading">Ways to help</h2><!-- /wp:heading --><!-- wp:columns {"className":"vercel_action_grid"} -->
<div class="wp-block-columns vercel_action_grid"><!-- wp:column {"className":"vercel_action_card"} -->
<div class="wp-block-column vercel_action_card"><!-- wp:html --><span class="vercel_icon vercel_icon_adopt" aria-hidden="true"></span><!-- /wp:html --><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Adopt</h3><!-- /wp:heading --><!-- wp:paragraph --><p>Open your home to a dog who's ready for their next chapter.</p><!-- /wp:paragraph --><!-- wp:paragraph {"className":"vercel_action_link"} --><p class="vercel_action_link"><a href="#contact">Contact us to learn more</a></p><!-- /wp:paragraph --></div>
<!-- /wp:column --><!-- wp:column {"className":"vercel_action_card"} -->
<div class="wp-block-column vercel_action_card"><!-- wp:html --><span class="vercel_icon vercel_icon_volunteer" aria-hidden="true"></span><!-- /wp:html --><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Volunteer</h3><!-- /wp:heading --><!-- wp:paragraph --><p>Foster, transport, or lend a hand at events — there's a role for every schedule.</p><!-- /wp:paragraph --><!-- wp:paragraph {"className":"vercel_action_link"} --><p class="vercel_action_link"><a href="#contact">Contact us to learn more</a></p><!-- /wp:paragraph --></div>
<!-- /wp:column --><!-- wp:column {"className":"vercel_action_card"} -->
<div class="wp-block-column vercel_action_card"><!-- wp:html --><span class="vercel_icon vercel_icon_donate" aria-hidden="true"></span><!-- /wp:html --><!-- wp:heading {"level":3} --><h3 class="wp-block-heading">Donate</h3><!-- /wp:heading --><!-- wp:paragraph --><p>Your support funds vet care, food, and shelter for dogs waiting for a home.</p><!-- /wp:paragraph --><!-- wp:paragraph {"className":"vercel_action_link"} --><p class="vercel_action_link"><a href="#contact">Contact us to learn more</a></p><!-- /wp:paragraph --></div>
<!-- /wp:column --></div>
<!-- /wp:columns --></div>
<!-- /wp:group --></div>
<!-- /wp:group -->

<!-- wp:group {"anchor":"contact","className":"vercel_section vercel_contact vercel_reveal","layout":{"type":"default"}} -->
<div id="contact" class="wp-block-group vercel_section vercel_contact vercel_reveal"><!-- wp:group {"className":"vercel_section_inner","layout":{"type":"default"}} -->
<div class="wp-block-group vercel_section_inner"><!-- wp:columns {"className":"vercel_contact_grid"} -->
<div class="wp-block-columns vercel_contact_grid"><!-- wp:column --><div class="wp-block-column"><!-- wp:paragraph {"className":"vercel_eyebrow"} --><p class="vercel_eyebrow">Contact</p><!-- /wp:paragraph --><!-- wp:heading --><h2 class="wp-block-heading">We’d love to hear from you</h2><!-- /wp:heading --><!-- wp:paragraph {"className":"vercel_lead"} --><p class="vercel_lead">Questions about adopting, volunteering, or supporting Yuki's Rescue? Reach out any time — we’re a small, volunteer-run team and we answer personally.</p><!-- /wp:paragraph --></div><!-- /wp:column --><!-- wp:column {"className":"vercel_contact_details"} -->
<div class="wp-block-column vercel_contact_details"><!-- wp:paragraph {"className":"vercel_contact_map"} --><p class="vercel_contact_map"><a href="https://www.google.com/maps/search/?api=1&amp;query=1221%20Coral%20Reef%20Place%2C%20Alameda%2C%20CA" target="_blank" rel="noreferrer noopener">1221 Coral Reef Place, Alameda, CA</a></p><!-- /wp:paragraph --><!-- wp:paragraph {"className":"vercel_contact_phone"} --><p class="vercel_contact_phone"><a href="tel:5103506924">510.350.6924</a></p><!-- /wp:paragraph --><!-- wp:button {"className":"vercel_call_button"} --><div class="wp-block-button vercel_call_button"><a class="wp-block-button__link wp-element-button" href="tel:5103506924">Call Yuki's Rescue</a></div><!-- /wp:button --></div>
<!-- /wp:column --></div>
<!-- /wp:columns --></div>
<!-- /wp:group --></div>
<!-- /wp:group -->
```

### Step 5: Run tests and commit

Run `npm run test:vercel`. Expected: five tests pass. Commit:

```bash
git add theme/yukis/templates/front-page.html theme/yukis/parts \
  theme/yukis/patterns/vercel_landing.php theme/yukis/tests
git commit -m "feat: add editable Vercel landing blocks (YUKI-ndkaskno)"
```

## Task 4: Implement faithful responsive styling and reveal behavior

**Depends on:** Task 3

**FP child:** `YUKI-zlktmwqy`

**Files:**

- Modify: `theme/yukis/tests/vercel_theme.test.mjs`
- Create: `theme/yukis/assets/css/vercel_styles.css`
- Create: `theme/yukis/assets/js/vercel_reveal.js`

### Step 1: Add failing presentation assertions

Append:

```js
test('presentation preserves source breakpoints and safe enhancement', async () => {
  const css = await text('theme/yukis/assets/css/vercel_styles.css');
  for (const [name, value] of Object.entries(contract.colors)) {
    assert.ok(css.includes(`--${name}: ${value}`), name);
  }
  for (const token of [
    '@media (min-width: 40rem)',
    '@media (min-width: 64rem)',
    '@media (prefers-reduced-motion: reduce)',
    'scroll-margin-top: 5rem',
    'max-width: 72rem',
    'transition-duration: 700ms',
  ]) assert.ok(css.includes(token), token);

  const js = await text('theme/yukis/assets/js/vercel_reveal.js');
  assert.match(js, /IntersectionObserver/);
  assert.match(js, /threshold:\s*0\.15/);
  assert.match(js, /vercel_reveal_visible/);
  assert.match(js, /prefers-reduced-motion/);
});
```

Run `npm run test:vercel`. Expected: failure because both files are absent.

### Step 2: Create the stylesheet

Create `vercel_styles.css` with this complete rule set, expanding the grouped
selectors only when WordPress editor scoping requires it:

```css
:root {
  --vercel_background: #faf8f4;
  --vercel_foreground: #2b2a28;
  --vercel_muted: #f1ece2;
  --vercel_muted_foreground: #6b6459;
  --vercel_border: #e4ddd0;
  --vercel_accent: #8a7998;
  --vercel_sage: #7e8c72;
  --vercel_white: #ffffff;
}
html { scroll-behavior: smooth; }
.vercel_main { margin: 0; max-width: none; background: var(--vercel_background); color: var(--vercel_foreground); font-family: Inter, Arial, sans-serif; }
.vercel_main h1, .vercel_main h2, .vercel_main h3, .vercel_header_name, .vercel_footer_identity { font-family: Fraunces, Georgia, serif; font-weight: 500; }
.vercel_header { position: sticky; top: 0; z-index: 40; border-bottom: 1px solid color-mix(in srgb, var(--vercel_border) 70%, transparent); background: color-mix(in srgb, var(--vercel_background) 90%, transparent); backdrop-filter: blur(12px); }
.vercel_header_inner, .vercel_section_inner, .vercel_footer_inner { width: min(100% - 2.5rem, 72rem); margin-inline: auto; }
.vercel_header_inner { min-height: 4.75rem; display: flex; align-items: center; justify-content: space-between; gap: 1rem; }
.vercel_header_brand { display: flex; align-items: center; gap: .75rem; }
.vercel_header_logo { width: 2.5rem; margin: 0; }
.vercel_header_name { font-size: 1.25rem; }
.vercel_header nav { font-size: .8125rem; font-weight: 500; letter-spacing: .025em; }
.vercel_header .wp-block-navigation__container { gap: .875rem; flex-wrap: nowrap; }
.vercel_section { scroll-margin-top: 5rem; padding-block: 5rem; }
.vercel_section_muted { border-top: 1px solid var(--vercel_border); background: color-mix(in srgb, var(--vercel_muted) 60%, transparent); }
.vercel_hero { padding-block: 3.5rem 4rem; }
.vercel_hero_grid, .vercel_contact_grid { display: grid; align-items: center; gap: 3rem; }
.vercel_hero_copy { order: 2; }
.vercel_hero_art { order: 1; position: relative; width: min(72%, 18.75rem); margin-inline: auto; }
.vercel_hero_art::before { content: ""; position: absolute; inset: 10%; border-radius: 50%; background: color-mix(in srgb, var(--vercel_sage) 20%, transparent); filter: blur(70px); }
.vercel_hero_art img { position: relative; filter: drop-shadow(0 30px 45px rgba(43, 42, 40, .18)); }
.vercel_eyebrow { margin: 0; color: var(--vercel_sage); font-size: .75rem; font-weight: 500; letter-spacing: .2em; text-transform: uppercase; }
.vercel_hero h1 { max-width: 38rem; margin: 1.25rem 0 0; font-size: clamp(2.25rem, 6vw, 3.75rem); font-style: italic; line-height: 1.1; letter-spacing: -.025em; }
.vercel_lead { max-width: 28rem; margin-top: 1.5rem; color: var(--vercel_muted_foreground); font-size: 1.125rem; line-height: 1.625; }
.vercel_buttons { display: flex; flex-wrap: wrap; align-items: center; gap: 1.25rem; margin-top: 2.25rem; }
.vercel_button .wp-block-button__link, .vercel_call_button .wp-block-button__link { display: inline-flex; border-radius: 999px; background: var(--vercel_accent); color: var(--vercel_white); padding: .875rem 1.75rem; font-size: .875rem; font-weight: 500; text-decoration: none; }
.vercel_text_link { color: var(--vercel_foreground); font-size: .875rem; font-weight: 500; text-underline-offset: .25rem; }
.vercel_section h2 { max-width: 32rem; margin: 1rem 0 0; font-size: clamp(1.875rem, 5vw, 2.25rem); line-height: 1.2; }
.vercel_about_inner { max-width: 48rem; }
.vercel_about_text { margin-top: 1.5rem; color: var(--vercel_muted_foreground); font-size: 1.125rem; line-height: 1.625; }
.vercel_mission_grid, .vercel_action_grid { display: grid; gap: 3rem; margin-top: 3.5rem; }
.vercel_icon { width: 3rem; height: 3rem; display: grid; place-items: center; border: 1px solid var(--vercel_border); border-radius: 50%; color: var(--vercel_sage); }
.vercel_mission_item h3, .vercel_action_card h3 { margin: 1.25rem 0 0; font-size: 1.25rem; }
.vercel_mission_item p, .vercel_action_card p { color: var(--vercel_muted_foreground); font-size: .9375rem; line-height: 1.625; }
.vercel_action_grid { gap: 1.5rem; }
.vercel_action_card { height: 100%; display: flex; flex-direction: column; justify-content: space-between; border: 1px solid var(--vercel_border); border-radius: 1rem; background: var(--vercel_background); padding: 2rem; }
.vercel_action_card:hover { border-color: color-mix(in srgb, var(--vercel_accent) 50%, transparent); }
.vercel_action_link { margin-top: 2rem; color: var(--vercel_foreground); font-size: .875rem; font-weight: 500; text-decoration: none; }
.vercel_action_link a::after { content: " →"; display: inline-block; transition: transform 150ms ease; }
.vercel_action_link a:hover::after { transform: translateX(.25rem); }
.vercel_contact_grid { align-items: start; }
.vercel_contact_details { display: grid; gap: 1.25rem; }
.vercel_contact_details a { color: var(--vercel_foreground); text-decoration: none; }
.vercel_footer { border-top: 1px solid var(--vercel_border); background: var(--vercel_background); }
.vercel_footer_inner { padding-block: 3rem; }
.vercel_footer_top { display: flex; flex-direction: column; gap: 2rem; }
.vercel_footer_identity { color: var(--vercel_foreground); font-size: 1rem; }
.vercel_footer p { margin: .25rem 0; color: var(--vercel_muted_foreground); font-size: .875rem; }
.vercel_footer_legal { margin-top: 2.5rem; padding-top: 1.5rem; border-top: 1px solid var(--vercel_border); font-size: .75rem; }
.vercel_reveal { opacity: 1; transform: none; }
.vercel_reveal_pending { opacity: 0; transform: translateY(1.25rem); }
.vercel_reveal_visible { opacity: 1; transform: none; transition: opacity 700ms ease-out, transform 700ms ease-out; transition-duration: 700ms; }
@media (min-width: 40rem) {
  .vercel_header_inner, .vercel_section_inner, .vercel_footer_inner { width: min(100% - 4rem, 72rem); }
  .vercel_header_name { display: block; }
  .vercel_header .wp-block-navigation__container { gap: 2rem; }
  .vercel_section { padding-block: 7rem; }
  .vercel_mission_grid, .vercel_action_grid { grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 2rem; }
  .vercel_footer_legal { display: flex; justify-content: space-between; gap: 1rem; }
}
@media (min-width: 64rem) {
  .vercel_hero { padding-top: 6rem; }
  .vercel_hero_grid, .vercel_contact_grid { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 4rem; }
  .vercel_hero_copy { order: 1; }
  .vercel_hero_art { order: 2; width: 100%; max-width: 36.25rem; }
  .vercel_contact_grid { gap: 5rem; }
}
@media (max-width: 39.999rem) {
  .vercel_header_name { display: none; }
}
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  .vercel_reveal_pending, .vercel_reveal_visible { opacity: 1; transform: none; transition: none; }
}
```

Add these source-derived mask rules immediately before the media queries:

```css
.vercel_icon::before, .vercel_contact_map::before, .vercel_contact_phone::before {
  content: ""; display: inline-block; width: 1.25rem; height: 1.25rem;
  background: var(--vercel_sage); mask: var(--vercel_icon_svg) center / contain no-repeat;
}
.vercel_icon_rescue::before, .vercel_icon_donate::before {
  --vercel_icon_svg: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='none' stroke='black' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round' d='M12 20s-7.2-4.6-9.5-9.2C1 7.6 2.6 4.5 5.8 4c2-.3 3.7.7 6.2 3 2.5-2.3 4.2-3.3 6.2-3 3.2.5 4.8 3.6 3.3 6.8C19.2 15.4 12 20 12 20Z'/%3E%3C/svg%3E");
}
.vercel_icon_rehabilitation::before {
  --vercel_icon_svg: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cg fill='none' stroke='black' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M12 21v-8.5'/%3E%3Cpath d='M12 12.5c0-3.6-2.9-6.5-6.5-6.5a6.5 6.5 0 0 0 6.5 6.5Z'/%3E%3Cpath d='M12 12.5c0-3.6 2.9-6.5 6.5-6.5a6.5 6.5 0 0 1-6.5 6.5Z'/%3E%3C/g%3E%3C/svg%3E");
}
.vercel_icon_rehoming::before, .vercel_icon_adopt::before {
  --vercel_icon_svg: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cg fill='none' stroke='black' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M4 11.5 12 4l8 7.5'/%3E%3Cpath d='M6 10v9.5a1 1 0 0 0 1 1h3.5v-6h3v6H17a1 1 0 0 0 1-1V10'/%3E%3C/g%3E%3C/svg%3E");
}
.vercel_icon_volunteer::before {
  --vercel_icon_svg: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cg fill='none' stroke='black' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M3.5 12.5 6 10a1.6 1.6 0 0 1 2.2 0l3.3 3.2M20.5 12.5 18 10a1.6 1.6 0 0 0-2.2 0l-3.3 3.2M8 15.5c1.3 1.6 2.7 2.8 4 2.8s2.7-1.2 4-2.8m-4.5-2.3-3-3a1.4 1.4 0 0 1 2-2l3.3 3.2m-1.3 1.8 3-3a1.4 1.4 0 0 0-2-2l-3.3 3.2'/%3E%3C/g%3E%3C/svg%3E");
}
.vercel_contact_map { display: flex; align-items: flex-start; gap: .875rem; }
.vercel_contact_map::before {
  --vercel_icon_svg: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cg fill='none' stroke='black' stroke-width='1.5'%3E%3Cpath d='M12 21s7-6.1 7-11.5A7 7 0 0 0 5 9.5C5 14.9 12 21 12 21Z'/%3E%3Ccircle cx='12' cy='9.5' r='2.5'/%3E%3C/g%3E%3C/svg%3E");
}
.vercel_contact_phone { display: flex; align-items: center; gap: .875rem; }
.vercel_contact_phone::before {
  --vercel_icon_svg: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='none' stroke='black' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round' d='M5 4h3.2l1.2 4.4-2 1.6a12 12 0 0 0 5.6 5.6l1.6-2 4.4 1.2V18a2 2 0 0 1-2 2C10.7 20 4 13.3 4 5a2 2 0 0 1 1-1Z'/%3E%3C/svg%3E");
}
```

### Step 3: Create the reveal enhancement

Create `vercel_reveal.js`:

```js
(() => {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const nodes = [...document.querySelectorAll('.vercel_reveal')];
  if (reduced || !('IntersectionObserver' in window)) return;

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.remove('vercel_reveal_pending');
      entry.target.classList.add('vercel_reveal_visible');
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.15 });

  for (const node of nodes) {
    const rect = node.getBoundingClientRect();
    if (rect.top < window.innerHeight && rect.bottom > 0) continue;
    node.classList.add('vercel_reveal_pending');
    observer.observe(node);
  }
})();
```

### Step 4: Verify and commit

Run:

```bash
npm run test:vercel
node --check theme/yukis/assets/js/vercel_reveal.js
```

Expected: six tests pass and Node reports no syntax error. Commit:

```bash
git add theme/yukis/assets theme/yukis/tests
git commit -m "feat: match Vercel presentation and motion (YUKI-ndkaskno)"
```

## Task 5: Guard nested export assets

**Depends on:** Task 4

**FP child:** `YUKI-kqdjfulr`

**Files:**

- Modify: `deploy/wordpress/tests/test-publish.sh`
- Modify: `deploy/wordpress/publish.sh`
- Modify: `deploy/wordpress/ss-configure.php`

### Step 1: Add the failing CSS dependency regression

In `test-publish.sh`, add a test after the missing-HTML-asset test:

```bash
echo "test: refuses an export whose CSS references a missing local asset"
setup
valid_export
echo '@font-face{src:url("/wp-content/themes/yukis/assets/fonts/gone.woff2")}' \
  > "$EXPORT_DIR/wp-includes/css/a.css"
OUT="$(SKIP_PUSH=1 "$PUBLISH" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "names the missing font" "$(echo "$OUT" | grep -c 'gone.woff2')" "1"
assert "repo untouched" "$(cat "$REPO_DIR/site/index.html")" "old"
teardown
```

Run `bash deploy/wordpress/tests/test-publish.sh`. Expected: this new test fails
because the current guard only scans HTML.

### Step 2: Scan exported HTML and CSS for root-relative assets

In `publish.sh`, change the `find` expression feeding the existing extraction
pipeline from only `*.html` to:

```bash
find "$EXPORT_DIR" -type f \( -name '*.html' -o -name '*.css' \) -print0
```

Keep the existing normalization, `/wp-includes|wp-content` restriction, file
shape check, and missing-file error. This is the smallest fix that protects the
new fonts without broadening the guard to remote URLs.

### Step 3: Explicitly crawl the migration assets

Append these paths to `$extra_assets` in `ss-configure.php`:

```php
'/wp-content/themes/yukis/assets/css/vercel_styles.css',
'/wp-content/themes/yukis/assets/js/vercel_reveal.js',
'/wp-content/themes/yukis/assets/fonts/vercel_inter.woff2',
'/wp-content/themes/yukis/assets/fonts/vercel_fraunces.woff2',
'/wp-content/themes/yukis/assets/fonts/vercel_fraunces_italic.woff2',
'/wp-content/themes/yukis/assets/images/vercel_logo.png',
'/wp-content/themes/yukis/assets/images/vercel_hero.svg',
```

### Step 4: Verify and commit

Run:

```bash
bash deploy/wordpress/tests/test-publish.sh
bash deploy/wordpress/tests/test-backup.sh
npm run test:vercel
```

Expected: all publisher, backup, and Vercel tests pass. Commit:

```bash
git add deploy/wordpress/publish.sh deploy/wordpress/ss-configure.php \
  deploy/wordpress/tests/test-publish.sh
git commit -m "fix: guard Vercel export dependencies (YUKI-ndkaskno)"
```

## Task 6: Add a guarded Home-page migration command

**Depends on:** Tasks 3 and 5

**FP child:** `YUKI-ltelmcfa`

**Files:**

- Create: `deploy/wordpress/vercel_migrate_home.sh`
- Create: `deploy/wordpress/tests/test-vercel-migrate.sh`
- Modify: `deploy/wordpress/wp-content-seed.sh`
- Delete: `deploy/wordpress/seed/home.html`
- Modify: `docs/DESIGNERS.md`

### Step 1: Write a failing fake-WP test

Create `test-vercel-migrate.sh` with a temporary `WP_RUNNER` fixture:

```bash
#!/usr/bin/env bash
set -uo pipefail
FAILURES=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATE="$HERE/../vercel_migrate_home.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert() {
  if [ "$2" = "$3" ]; then echo "  PASS $1"
  else echo "  FAIL $1: expected '$3', got '$2'"; FAILURES=$((FAILURES+1)); fi
}

cat > "$WORK/wp" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WP_LOG"
case "$1 $2" in
  'theme is-active') [ "${WP_MODE:-ok}" != inactive ] ;;
  'option get') echo 11 ;;
  'eval '*)
    [ "${WP_MODE:-ok}" != missing ] || { echo 'missing pattern' >&2; exit 1; }
    printf '%s' '<!-- wp:group --><div class="wp-block-group vercel_section">source</div><!-- /wp:group -->'
    ;;
  'post update') cat >> "$WP_STDIN" ;;
  'option update') : ;;
esac
FAKE
chmod +x "$WORK/wp"
export WP_RUNNER="$WORK/wp" WP_LOG="$WORK/log" WP_STDIN="$WORK/stdin"

echo 'test: explicit apply guard'
: > "$WP_LOG"
OUT="$("$MIGRATE" 2>&1)"; RC=$?
assert 'exit 1' "$RC" 1
assert 'no update' "$(grep -c 'post update' "$WP_LOG")" 0

echo 'test: active theme required'
: > "$WP_LOG"
OUT="$(WP_MODE=inactive APPLY=1 "$MIGRATE" 2>&1)"; RC=$?
assert 'exit 1' "$RC" 1
assert 'names theme' "$(echo "$OUT" | grep -ci yukis)" 1

echo 'test: registered pattern required'
: > "$WP_LOG"
OUT="$(WP_MODE=missing APPLY=1 "$MIGRATE" 2>&1)"; RC=$?
assert 'exit 1' "$RC" 1
assert 'no update' "$(grep -c 'post update' "$WP_LOG")" 0

echo 'test: updates configured front page from pattern'
: > "$WP_LOG"; : > "$WP_STDIN"
APPLY=1 "$MIGRATE" >/dev/null 2>&1; RC=$?
assert 'exit 0' "$RC" 0
assert 'updates page 11' "$(grep -c 'post update 11' "$WP_LOG")" 1
assert 'keeps front page' "$(grep -c 'option update page_on_front 11' "$WP_LOG")" 1
assert 'pipes pattern' "$(grep -c 'vercel_section' "$WP_STDIN")" 1

echo
[ "$FAILURES" -eq 0 ] && echo 'ALL TESTS PASSED' || {
  echo "$FAILURES FAILURE(S)"; exit 1;
}
```

Run the test. Expected: failure because the migration command does not exist.

### Step 2: Create the migration command

Create `vercel_migrate_home.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

WP_RUNNER="${WP_RUNNER:-}"
wp() {
  if [ -n "$WP_RUNNER" ]; then "$WP_RUNNER" "$@"
  else docker exec -u www-data yukis-wordpress wp "$@"
  fi
}

[ "${APPLY:-0}" = "1" ] || {
  echo "ERROR: set APPLY=1 to replace the current Home page" >&2
  exit 1
}
wp theme is-active yukis || {
  echo "ERROR: the yukis theme must be active" >&2
  exit 1
}

HOME_ID="$(wp option get page_on_front | tr -d '\r')"
[ -n "$HOME_ID" ] && [ "$HOME_ID" != "0" ] || {
  echo "ERROR: no static front page is configured" >&2
  exit 1
}

CONTENT="$(wp eval '$p = WP_Block_Patterns_Registry::get_instance()->get_registered("yukis/vercel_landing"); if (!$p || empty($p["content"])) { fwrite(STDERR, "missing yukis/vercel_landing pattern\n"); exit(1); } echo $p["content"];')"
[ -n "$CONTENT" ] || { echo "ERROR: landing pattern is empty" >&2; exit 1; }

printf '%s' "$CONTENT" | wp post update "$HOME_ID" \
  --post_title="Yuki's Rescue | Alameda, CA" -
wp option update show_on_front page >/dev/null
wp option update page_on_front "$HOME_ID" >/dev/null
echo "updated front page $HOME_ID from yukis/vercel_landing"
```

Make it executable.

### Step 3: Update designer documentation

First update `wp-content-seed.sh` so future rebuilds cannot restore the obsolete
purple Home page. Replace its `create_page home ... "$SEED_DIR/home.html"` call
with creation of an empty Home page when absent, then invoke the same guarded
migration command:

```bash
HOME_ID="$(page_id home)"
if [ -z "$HOME_ID" ]; then
  wp post create --post_type=page --post_status=publish --post_name=home \
    --post_title="Yuki's Rescue | Alameda, CA" --post_content=''
fi
APPLY=1 "$(dirname "${BASH_SOURCE[0]}")/vercel_migrate_home.sh"
```

Retain the three existing placeholder-page calls and front-page option updates.
Delete `deploy/wordpress/seed/home.html`; the registered
`yukis/vercel_landing` pattern is now the only deterministic Home source. Extend
`test-vercel-migrate.sh` to assert that `wp-content-seed.sh` calls
`vercel_migrate_home.sh` and no longer mentions `seed/home.html`.

### Step 4: Update designer documentation

Change the page list in `docs/DESIGNERS.md` to explain that Home is a one-page
landing page with About, Mission, Get Involved, and Contact sections. State that
header links scroll to those sections and that `/about/`, `/rescue/`, and
`/feedback/` remain separate legacy pages but are not in the Vercel header.

### Step 5: Verify and commit

Run:

```bash
bash deploy/wordpress/tests/test-vercel-migrate.sh
npm run test:vercel
drift check
```

Expected: the migration-script cases and Vercel tests pass; drift reports `ok`.
Commit:

```bash
git add deploy/wordpress/vercel_migrate_home.sh \
  deploy/wordpress/tests/test-vercel-migrate.sh \
  deploy/wordpress/wp-content-seed.sh deploy/wordpress/seed/home.html \
  docs/DESIGNERS.md
git commit -m "feat: add guarded Vercel home migration (YUKI-ndkaskno)"
```

## Task 7: Install on WordPress and produce a held preview

**Depends on:** Tasks 2 through 6

**FP child:** `YUKI-ecguzisx`

**Files changed remotely:** `/opt/wordpress`, the `wp_themes` volume, and the
existing WordPress Home page. Production remains unchanged during this task.

### Step 1: Run the full local gate

```bash
npm run test:vercel
bash deploy/wordpress/tests/test-vercel-migrate.sh
bash deploy/wordpress/tests/test-publish.sh
bash deploy/wordpress/tests/test-backup.sh
npm --prefix worker-contact test
npm --prefix worker-dmarc test
git diff --check origin/main...HEAD
drift check
```

Expected: every suite passes, the diff check is empty, and drift reports `ok`.

### Step 2: Stop automatic production publication and take a backup

```bash
ssh node2.lan 'docker stop yukis-publisher'
ssh node2.lan 'docker exec yukis-backup /backup.sh'
```

Expected: publisher reports stopped and backup prints the new database, uploads,
and theme archive names. Do not continue if backup fails.

### Step 3: Synchronize the theme and migration files

```bash
rsync -av --delete theme/yukis/ node2.lan:/tmp/vercel_yukis_theme/
rsync -av deploy/wordpress/vercel_migrate_home.sh \
  deploy/wordpress/ss-configure.php node2.lan:/opt/wordpress/
ssh node2.lan 'docker cp /tmp/vercel_yukis_theme/. yukis-wordpress:/var/www/html/wp-content/themes/yukis/ && docker exec yukis-wordpress chown -R www-data:www-data /var/www/html/wp-content/themes/yukis && docker exec -u www-data yukis-wordpress wp theme is-active yukis'
```

Expected: the final command exits 0. The `--delete` target is an explicit `/tmp`
directory, not the live theme volume; `docker cp` then overlays the reviewed
theme without deleting unrelated WordPress data.

### Step 4: Apply the page migration and export configuration

```bash
ssh node2.lan 'cd /opt/wordpress && APPLY=1 ./vercel_migrate_home.sh'
ssh node2.lan 'docker cp /opt/wordpress/ss-configure.php yukis-wordpress:/tmp/ss-configure.php && docker exec -u www-data yukis-wordpress wp eval-file /tmp/ss-configure.php'
```

Expected: the first command names the unchanged front-page ID; the second lists
the new prefixed asset URLs.

### Step 5: Generate but do not publish the export

Before exporting, open the Home page in the block editor. Confirm that the hero
description, first action-card link, and hero logo can each be selected and
changed without opening the code editor. Use Preview to observe the temporary
changes, then discard them without saving. This verifies editability while
keeping the approved source content unchanged.

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp eval "Simply_Static\\Plugin::instance()->run_static_export();"'
rsync -av --delete node2.lan:/opt/wordpress/export/out/ tmp/vercel_preview/
```

Confirm `yukis-publisher` remains stopped. Serve the preview locally:

```bash
npx wrangler dev --assets tmp/vercel_preview
```

### Step 6: Verify the held artifact

At widths 375, 768, and 1440 pixels, compare the local preview with the Vercel
source. Verify layout, source copy, logo scale, fonts, colors, hover/focus,
sticky anchor offsets, reduced motion, phone link, and map link.

Run artifact checks:

```bash
rg -n '_next|vercel\.app|control\.yukisrescue\.org' tmp/vercel_preview
rg -n 'id="(top|about|mission|get-involved|contact)"' tmp/vercel_preview/index.html
find tmp/vercel_preview/wp-content/themes/yukis/assets -type f | sort
```

Expected: the first command has no matches; the second finds all five IDs; the
third lists CSS, JavaScript, three fonts, and two images.

## Task 8: Publish and verify production

**Depends on:** Task 7 and approval of the held preview

**FP child:** `YUKI-lmwtygsc`

### Step 1: Integrate the reviewed source before publishing generated output

Use `superpowers:finishing-a-development-branch` to present the integration
choice. The selected path must put every source, test, theme, script, and docs
commit on `origin/main` before the publisher is restarted. After integration,
verify from the primary worktree:

```bash
git fetch origin main
git merge-base --is-ancestor codex/vercel-wordpress-migration origin/main
git status --short --branch
```

Expected: the ancestor command exits 0 and the primary worktree has no
uncommitted changes. A merged pull request label alone is not sufficient.

### Step 2: Start the publisher and watch one deployment

```bash
ssh node2.lan 'docker start yukis-publisher'
ssh node2.lan 'docker logs -f --since 1m yukis-publisher'
```

Expected: one publish commit, one Wrangler version upload/deploy, and the live
verification marker. Stop following logs after the verified message; do not
restart or trigger a second export.

### Step 3: Refresh after the publisher commit

```bash
git fetch origin main
git merge --ff-only origin/main
git status --short --branch
```

The publisher commit changes `site/`; do not manufacture a second local copy or
amend it. The fast-forward must succeed; if it does not, stop and inspect the
new divergence before changing history.

### Step 4: Run final production acceptance

```bash
curl -fsSL https://www.yukisrescue.org/ -o /tmp/vercel_production.html
rg -n 'Second chances for dogs|id="about"|id="mission"|id="get-involved"|id="contact"' /tmp/vercel_production.html
rg -n '_next|vercel\.app|control\.yukisrescue\.org' /tmp/vercel_production.html
npm run test:vercel
bash deploy/wordpress/tests/test-vercel-migrate.sh
bash deploy/wordpress/tests/test-publish.sh
bash deploy/wordpress/tests/test-backup.sh
npm --prefix worker-contact test
npm --prefix worker-dmarc test
drift check
```

Expected: source markers and five anchors are present; the forbidden-origin
search has no matches; all tests pass; drift reports `ok`.

### Step 5: Hand off

Do not manually commit `site/` if the publisher already committed it. If the
primary-worktree update leaves tracked source changes, inspect and commit only
the intended files:

```bash
git status --short --branch
git diff --check
```

Update FP child statuses and add a final comment to `YUKI-ndkaskno` containing
the commit IDs, exact test counts, Cloudflare version ID, production URL, and
rollback commit. Do not mark the parent done until local `HEAD` is contained by
`origin/main` and production passes the marker checks.
