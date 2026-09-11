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
