#!/usr/bin/env bash
set -euo pipefail

WP_RUNNER="${WP_RUNNER:-}"
wp() {
  if [ -n "$WP_RUNNER" ]; then "$WP_RUNNER" "$@"
  else docker exec -i -u www-data yukis-wordpress wp "$@"
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
