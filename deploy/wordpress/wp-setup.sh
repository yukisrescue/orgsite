#!/usr/bin/env bash
set -euo pipefail

# Runs WP-CLI inside the WordPress container.
wp() { docker exec -u www-data yukis-wordpress wp "$@"; }

: "${ADMIN_USER:?set ADMIN_USER}"
: "${ADMIN_EMAIL:?set ADMIN_EMAIL}"
: "${ADMIN_PASSWORD:?set ADMIN_PASSWORD}"
: "${SITE_URL:?set SITE_URL}"

if ! wp core is-installed 2>/dev/null; then
  wp core install \
    --url="$SITE_URL" \
    --title="Yuki's Rescue" \
    --admin_user="$ADMIN_USER" \
    --admin_email="$ADMIN_EMAIL" \
    --admin_password="$ADMIN_PASSWORD" \
    --skip-email
  echo "installed"
else
  echo "already installed"
fi

# Pretty permalinks. Must be set before content exists or URLs churn later.
wp rewrite structure '/%postname%/' --hard

# Remove default content that would otherwise be exported to production.
ids="$(wp post list --post_type=post --format=ids)"
[ -n "$ids" ] && wp post delete $ids --force || true
ids="$(wp post list --post_type=page --name=sample-page --format=ids)"
[ -n "$ids" ] && wp post delete $ids --force || true
wp plugin delete akismet hello 2>/dev/null || true

# Discourage indexing of the authoring host. The static export is unaffected,
# so production indexing is not impacted.
wp option update blog_public 0

echo "setup complete"
