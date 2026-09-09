<?php
/**
 * Plugin Name: Yuki's Rescue outbound mail identity
 * Description: Brands outgoing mail and points replies somewhere that receives.
 *
 * Neither sending subdomain has an MX record, so the From address cannot accept
 * mail: a reply to it bounces, and filters penalise From domains that cannot
 * receive. The root domain does receive (Cloudflare Email Routing handles
 * hello/admin/finance), so replies are directed there.
 *
 * The display name matters more than it looks. "editor" tells a spam filter and
 * a human nothing; the organisation's name is the single cheapest deliverability
 * and trust signal available.
 */

add_filter('wp_mail_from_name', function () {
    return "Yuki's Rescue";
}, 20);

add_filter('wp_mail', function ($args) {
    $headers = $args['headers'] ?? [];
    if (is_string($headers)) {
        $headers = array_filter(array_map('trim', explode("\n", $headers)));
    }
    if (!is_array($headers)) {
        $headers = [];
    }

    $hasReplyTo = false;
    foreach ($headers as $h) {
        if (stripos((string) $h, 'reply-to:') === 0) {
            $hasReplyTo = true;
            break;
        }
    }
    if (!$hasReplyTo) {
        $headers[] = "Reply-To: Yuki's Rescue <hello@yukisrescue.org>";
    }

    $args['headers'] = $headers;
    return $args;
}, 20);
