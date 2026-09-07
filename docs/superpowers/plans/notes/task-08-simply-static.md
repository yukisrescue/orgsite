# Task 8 — Simply Static characterization (measured 2026-09-07)

Version: Simply Static free tier, WordPress 6.9.4, PHP 8.3.

## Summary

The plugin's defaults produce **an export of the wrong website**. Four separate
faults had to be found and fixed before the export was usable. Each is recorded
here because none is discoverable without inspecting the output.

| | Defaults | After fixes |
|---|---|---|
| Size | 42 MB | **1.1 MB** |
| Files | 1,484 | **23** |
| HTML pages | 1 | **4** |
| Whose site | Synology DSM default page | Yuki's Rescue |
| Export time | 45 s | **5 s** |

## Fault 1 — the export was the Synology's default page

Simply Static fetches every page over real HTTP at `WP_SITEURL`. That request
left the container, went to Cloudflare, reached the Synology (which had no
reverse-proxy rule yet), and returned DSM's default page with HTTP 200. The
plugin dutifully saved it as `index.html`, along with 40 MB of DSM's own assets.

**This would have published the Synology login page to the nonprofit's
production site on the first designer publish.**

Setting `origin_url` alone did not fix it: with `Host: localhost` WordPress
issues a canonical redirect to the public HTTPS URL, so `/` returned 301.

**Fix, in `docker-compose.yml`:**

- `extra_hosts: ["control.yukisrescue.org:127.0.0.1"]` so the real hostname
  resolves to the container itself.
- A `wp-config` shim setting `$_SERVER['HTTPS'] = 'on'` for requests from
  `127.0.0.1` / `::1`, so the canonical redirect does not fire.
- `origin_url = http://control.yukisrescue.org`

This also pre-empts a second failure: once Cloudflare Access is enabled, fetches
that leave the box would be challenged rather than served.

## Fault 2 — three of four pages were never exported

`/about/`, `/rescue/`, `/feedback/` all recorded HTTP 404, because they were
being fetched through the same broken external path.

Additionally the planned orphan-page guard was already dead on arrival:
`wp-sitemap.xml` returns **404** because Task 5 sets `blog_public = 0` to
de-index the authoring host, and WordPress disables the sitemap when it does.
The plan's `additional_urls = .../wp-sitemap.xml` could never have worked.

**Fix:** enumerate published page permalinks directly and write them into
`additional_urls`. `ss-configure.php` regenerates the list, so pages added
later are covered by re-running it.

## Fault 3 — 1,480 unnecessary files

Only **4** assets are referenced by the four pages. The rest came from crawlers
that walk the filesystem rather than following links — `found_on_id` was empty
for every one of them.

With a git-based pipeline this matters more than disk: every publish would have
committed ~1,484 files, and the repository would grow without bound.

Default-active crawlers include `wp_includes` (40 MB of core JS/CSS),
`vendor_files`, `pagination`, `sitemap`, `text_file`, `taxonomy`, and `author`.

**Fix:** `crawlers = ['home','post_type','plugin_assets','theme_assets','uploads']`.

Disabling the list is not sufficient on its own — `Wp_Includes_Crawler::is_active()`
returns true unconditionally when the `smart_crawl` option is set, overriding the
selection. `smart_crawl` must also be set to `false`.

Verified after the change: all four referenced assets are still exported, picked
up by link-following rather than by directory walking.

## Fault 4 — the `author` crawler leaked the administrator username

Active by default, it publishes `/author/<admin-username>/` to the production
site. Now disabled; verified zero `author` paths in the export.

## No WP-CLI command

`wp help simply-static` reports no registered command on the free tier, so the
plan's watcher approach in Task 10 stands.

**However**, the export can be driven programmatically and runs *synchronously*
under WP-CLI:

```php
Simply_Static\Plugin::instance()->run_static_export();
```

with progress via `is_export_active()` and `get_archive_creation_job()`. This is
a better trigger than a background job dispatched over loopback HTTP, which
would be challenged once Access is enabled.

## Configuration is state, not code

Every setting above lives in the `simply-static` row of `wp_options`. A rebuild
on fresh volumes reverts to defaults that produce a broken export.

`deploy/wordpress/ss-configure.php` applies the whole configuration and is
committed. Run it after any rebuild, and after adding pages:

```bash
docker exec -u www-data yukis-wordpress wp eval-file /tmp/ss-configure.php
```

## Verified export contents (23 files)

- `index.html`, `about/index.html`, `rescue/index.html`, `feedback/index.html`
- 5 responsive variants of `hero_banner.jpg`
- 12 block stylesheets, for exactly the blocks in use
- 2 script modules (navigation view, interactivity runtime)

Checks that passed: correct site content, all links relative, **zero** absolute
`control.yukisrescue.org` references, no author archives, placeholders intact on
all three under-construction pages.
