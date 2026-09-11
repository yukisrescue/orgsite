<?php
/**
 * Simply Static configuration, as code.
 *
 * These settings live in the wp_options table, so a rebuild on fresh volumes
 * would otherwise silently revert to defaults that produce a broken export.
 * Run with:  wp eval-file /opt/wordpress/ss-configure.php
 *
 * Every value here was arrived at by measurement (see
 * docs/superpowers/plans/notes/task-08-simply-static.md). The defaults export
 * 1,484 files / 42MB of the wrong site; this configuration exports 23 files
 * / 1.1MB of the right one.
 */

$origin = 'http://control.yukisrescue.org';

$pages = get_posts([
    'post_type'   => 'page',
    'post_status' => 'publish',
    'numberposts' => -1,
    'fields'      => 'ids',
]);
$front = (int) get_option('page_on_front');
$urls  = [ $origin . '/' ];
foreach ($pages as $id) {
    if ((int) $id === $front) { continue; }
    $urls[] = $origin . '/' . get_post_field('post_name', $id) . '/';
}

$o = get_option('simply-static', []);

// Fetches must resolve to this container. compose maps the hostname to
// 127.0.0.1; without that the crawler exits to Cloudflare and exports the
// Synology's default page, or gets challenged by Access.
$o['origin_url'] = $origin;

// Relative links so the export works on www.yukisrescue.org, not just here.
$o['destination_url_type'] = 'relative';
$o['force_replace_url']    = true;

$o['delivery_method'] = 'local';
$o['local_dir']       = '/var/www/html/wp-content/uploads/simply-static/out/';

// Stale files must not survive a page deletion. rsync --delete on the repo
// side only makes the repo match the export, so the export must be authoritative.
$o['clear_directory_before_export'] = true;

// blog_public is 0 on the authoring host, which disables wp-sitemap.xml. The
// planned sitemap-based orphan guard is therefore dead; enumerate pages instead.
// Core assets that the URL extractor does not discover. WordPress emits some
// stylesheets through markup the extractor cannot parse (the block template
// skip-link among them), so they are referenced in the exported HTML but never
// fetched -- a 404 in production. publish.sh re-checks every referenced local
// path after each export, so a future miss fails the publish instead of
// reaching visitors.
$extra_assets = [
    '/wp-includes/css/dist/block-library/common.min.css',
    '/wp-includes/css/wp-block-template-skip-link.min.css',
    '/wp-content/themes/yukis/assets/css/vercel_styles.css',
    '/wp-content/themes/yukis/assets/js/vercel_reveal.js',
    '/wp-content/themes/yukis/assets/fonts/vercel_inter.woff2',
    '/wp-content/themes/yukis/assets/fonts/vercel_fraunces.woff2',
    '/wp-content/themes/yukis/assets/fonts/vercel_fraunces_italic.woff2',
    '/wp-content/themes/yukis/assets/images/vercel_logo.png',
    '/wp-content/themes/yukis/assets/images/vercel_hero.svg',
];
foreach ($extra_assets as $a) { $urls[] = $origin . $a; }

$o['additional_urls'] = implode("\n", $urls);

// The export directory lives under uploads; without this the uploads crawler
// sweeps the previous export into the next one.
$o['urls_to_exclude'] = 'wp-content/uploads/simply-static';

// Default crawlers walk all of wp-includes (40MB) and publish /author/<admin>/,
// leaking the administrator username. Referenced core assets are still picked
// up by link-following, which is verified after each export.
$o['crawlers']    = ['home', 'post_type', 'plugin_assets', 'theme_assets', 'uploads'];
$o['smart_crawl'] = false;   // forces the wp_includes crawler on regardless of the list

update_option('simply-static', $o);

echo "Simply Static configured\n";
echo "  origin_url:  {$o['origin_url']}\n";
echo "  crawlers:    " . implode(', ', $o['crawlers']) . "\n";
echo "  smart_crawl: " . var_export($o['smart_crawl'], true) . "\n";
echo "  urls (" . count($urls) . "):\n";
foreach ($urls as $u) { echo "    $u\n"; }
