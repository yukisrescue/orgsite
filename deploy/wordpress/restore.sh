#!/usr/bin/env bash
# Restore a WordPress backup. DESTRUCTIVE: replaces the current database and
# content. Run on the docker host, from the compose directory.
#
#   ./restore.sh <db-YYYYMMDD-HHMMSS.sql.gz> <content-YYYYMMDD-HHMMSS.tar.gz>
set -euo pipefail

DB_ARCHIVE="${1:?usage: restore.sh <db archive> <content archive>}"
CONTENT_ARCHIVE="${2:?usage: restore.sh <db archive> <content archive>}"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$COMPOSE_DIR"

[ -f "$DB_ARCHIVE" ]      || { echo "missing: $DB_ARCHIVE" >&2; exit 1; }
[ -f "$CONTENT_ARCHIVE" ] || { echo "missing: $CONTENT_ARCHIVE" >&2; exit 1; }

# Verify the archives before destroying anything with them.
gzip -t "$DB_ARCHIVE"
tar tzf "$CONTENT_ARCHIVE" >/dev/null
echo "archives verified"

set -a; . ./.env; set +a

if [ "${ASSUME_YES:-0}" != "1" ]; then
  echo
  echo "This REPLACES the current WordPress database and content."
  read -r -p "Type RESTORE to continue: " confirm
  [ "$confirm" = "RESTORE" ] || { echo "aborted"; exit 1; }
fi

echo "restoring database..."
gunzip -c "$DB_ARCHIVE" | docker exec -i yukis-mariadb \
  mariadb --user="$WP_DB_USER" --password="$WP_DB_PASSWORD" "$WP_DB_NAME"

echo "restoring uploads and themes..."
docker run --rm \
  -v wordpress_wp_uploads:/data/uploads \
  -v wordpress_wp_themes:/data/themes \
  -v "$(cd "$(dirname "$CONTENT_ARCHIVE")" && pwd)":/archives:ro \
  alpine:3.20 \
  tar xzf "/archives/$(basename "$CONTENT_ARCHIVE")" -C /data

docker exec yukis-wordpress chown -R www-data:www-data \
  /var/www/html/wp-content/uploads /var/www/html/wp-content/themes

docker restart yukis-wordpress >/dev/null
echo "restore complete; WordPress restarted"
