<?php
/**
 * Plugin Name: Yuki's Rescue export URL maintenance
 * Description: Keeps Simply Static's additional_urls in step with published content.
 *
 * Simply Static's post_type crawler discovers pages at their public HTTPS
 * permalink. Those fetches leave the container, reach Cloudflare, and are
 * challenged by Access, so they are discovered but never fetched -- the page is
 * silently missing from the export with no error anywhere.
 *
 * Only URLs rebased onto the origin (http://control.yukisrescue.org, pinned to
 * 127.0.0.1 inside the container) are actually fetchable. This rebuilds that
 * list whenever content changes, so a designer publishing a new page does not
 * have to know any of the above.
 *
 * Without this, the first thing a new designer does -- add a page -- fails in
 * the least debuggable way possible: the page looks published, and simply never
 * appears on the live site.
 */

const YUKIS_EXPORT_EXTRA_ASSETS = [
    // Emitted through markup Simply Static's URL extractor cannot parse.
    '/wp-includes/css/dist/block-library/common.min.css',
    '/wp-includes/css/wp-block-template-skip-link.min.css',
];

function yukis_export_origin(): string {
    $opts = get_option('simply-static');
    $origin = is_array($opts) ? trim((string) ($opts['origin_url'] ?? '')) : '';
    if ($origin === '') {
        // Fall back to the site URL forced to http, which is what resolves
        // locally. https would exit to Cloudflare and be challenged.
        $origin = set_url_scheme(home_url(), 'http');
    }
    return rtrim($origin, '/');
}

function yukis_rebuild_export_urls(): void {
    $opts = get_option('simply-static');
    if (!is_array($opts)) {
        return;
    }

    $origin = yukis_export_origin();
    $urls   = [$origin . '/'];

    $front = (int) get_option('page_on_front');
    $pages = get_posts([
        'post_type'   => 'page',
        'post_status' => 'publish',
        'numberposts' => -1,
        'fields'      => 'ids',
    ]);

    foreach ($pages as $id) {
        if ((int) $id === $front) {
            continue;   // already covered by the origin root
        }
        $path = wp_parse_url(get_permalink($id), PHP_URL_PATH);
        if (is_string($path) && $path !== '') {
            $urls[] = $origin . $path;
        }
    }

    foreach (YUKIS_EXPORT_EXTRA_ASSETS as $asset) {
        $urls[] = $origin . $asset;
    }

    $urls = array_values(array_unique($urls));
    $new  = implode("\n", $urls);

    if (($opts['additional_urls'] ?? null) !== $new) {
        $opts['additional_urls'] = $new;
        update_option('simply-static', $opts);
    }
}

// Any transition into or out of "publish" changes what should be exported.
add_action('transition_post_status', function ($new_status, $old_status, $post) {
    if (!$post instanceof WP_Post || $post->post_type !== 'page') {
        return;
    }
    if ($new_status === 'publish' || $old_status === 'publish') {
        yukis_rebuild_export_urls();
    }
}, 10, 3);

add_action('deleted_post', function ($post_id, $post = null) {
    if ($post instanceof WP_Post && $post->post_type !== 'page') {
        return;
    }
    yukis_rebuild_export_urls();
}, 10, 2);

// Permalink structure or front-page changes rewrite every path.
add_action('update_option_permalink_structure', 'yukis_rebuild_export_urls');
add_action('update_option_page_on_front', 'yukis_rebuild_export_urls');

// Belt and braces: rebuild immediately before an export runs, so a list that
// drifted for any reason is corrected rather than silently shipping a gap.
add_action('ss_before_perform_archive_action', 'yukis_rebuild_export_urls');
add_action('simply_static_site_export_started', 'yukis_rebuild_export_urls');
