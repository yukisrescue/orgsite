#!/usr/bin/env bash
# Recover plugin files from a detached anonymous WordPress volume on node2.
# Inspect candidates with plugin-volume-inventory.sh before running this.
set -euo pipefail
umask 077

SOURCE_VOLUME="${1:?usage: bash restore-plugins-from-volume.sh <detached-volume-id>}"
DEST_VOLUME=wordpress_wp_plugins
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

docker volume inspect "$SOURCE_VOLUME" >/dev/null
if docker volume inspect "$DEST_VOLUME" >/dev/null 2>&1; then
  echo "ERROR: $DEST_VOLUME already exists. Inspect it before retrying; no files were changed." >&2
  exit 1
fi

# Do not accept a similarly named but unrelated volume. The inventory script
# looks for this layout, and this check pins the expected missing plugin.
docker run --rm --network none \
  --mount "type=volume,source=$SOURCE_VOLUME,target=/candidate,readonly" \
  alpine:3.20 test -f /candidate/wp-content/plugins/simply-static/simply-static.php

snapshot="$HERE/current-plugins-before-recovery-$(date -u +%Y%m%d-%H%M%S).tar.gz"
docker exec yukis-wordpress tar czf - -C /var/www/html/wp-content plugins > "$snapshot"
gzip -t "$snapshot"
echo "Saved current plugin files to $snapshot"

# Use Compose's expected labels so the pre-created volume is recognized by
# this project's compose file. SOURCE_VOLUME remains untouched.
docker volume create \
  --label com.docker.compose.project=wordpress \
  --label com.docker.compose.volume=wp_plugins \
  "$DEST_VOLUME" >/dev/null

docker run --rm --network none \
  --mount "type=volume,source=$SOURCE_VOLUME,target=/candidate,readonly" \
  --mount "type=volume,source=$DEST_VOLUME,target=/plugins" \
  alpine:3.20 sh -c \
  'cp -a /candidate/wp-content/plugins/. /plugins/ && test -f /plugins/simply-static/simply-static.php'

# Compose now mounts the named volume into WordPress. Do not use -V or down -v.
docker compose up -d wordpress backup
docker exec yukis-wordpress chown -R www-data:www-data /var/www/html/wp-content/plugins

for plugin in simply-static daggerhart-openid-connect-generic send-emails-with-resend two-factor; do
  docker exec -u www-data yukis-wordpress wp plugin activate "$plugin"
done

docker exec -u www-data yukis-wordpress wp plugin list
echo "Recovered plugins from $SOURCE_VOLUME into $DEST_VOLUME."
