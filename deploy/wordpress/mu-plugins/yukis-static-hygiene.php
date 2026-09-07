<?php
/**
 * Plugin Name: Yuki's Rescue static-export hygiene
 * Description: Removes output that the static export cannot resolve.
 *
 * WordPress injects the emoji polyfill through a window._wpemojiSettings JSON
 * blob rather than a plain script src. Simply Static's URL extractor does not
 * parse it, so the files are referenced in the exported HTML but never fetched,
 * producing 404s in production. The polyfill is unnecessary on any browser this
 * site supports, so it is removed rather than exported.
 */

// Front end
remove_action('wp_head', 'print_emoji_detection_script', 7);
remove_action('wp_print_styles', 'print_emoji_styles');
// Admin
remove_action('admin_print_scripts', 'print_emoji_detection_script');
remove_action('admin_print_styles', 'print_emoji_styles');
// Feeds and email
remove_filter('the_content_feed', 'wp_staticize_emoji');
remove_filter('comment_text_rss', 'wp_staticize_emoji');
remove_filter('wp_mail', 'wp_staticize_emoji_for_email');

// Drop the emoji entry from the script-loader's TinyMCE plugin list too.
add_filter('tiny_mce_plugins', function ($plugins) {
    return is_array($plugins) ? array_diff($plugins, ['wpemoji']) : [];
});

// Do not emit resource hints for the emoji CDN.
add_filter('wp_resource_hints', function ($urls, $relation) {
    if ('dns-prefetch' === $relation) {
        $urls = array_filter($urls, function ($u) {
            return false === strpos((string) $u, 's.w.org');
        });
    }
    return $urls;
}, 10, 2);
