<?php
/**
 * Plugin Name: Yuki's Rescue role capabilities
 * Description: Grants Editors access to the Site Editor, and nothing else.
 *
 * WordPress Editors cannot open Appearance -> Editor without
 * edit_theme_options, so out of the box the designers could write content but
 * not change how the site looks -- which is the main reason they are here.
 *
 * This grants exactly that one capability. It deliberately does NOT grant
 * install_plugins, activate_plugins, switch_themes, edit_files or
 * manage_options: the containment that makes unreviewed publishing acceptable
 * depends on designers being unable to execute code on the server.
 *
 * Applied as a must-use plugin rather than a database role edit so it survives
 * a restore onto fresh volumes. Role capabilities live in wp_options and would
 * otherwise silently revert.
 */

add_action('init', function () {
    $role = get_role('editor');
    if (!$role) {
        return;
    }
    if (!$role->has_cap('edit_theme_options')) {
        $role->add_cap('edit_theme_options');
    }
});
