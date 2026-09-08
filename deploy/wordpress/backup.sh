#!/usr/bin/env bash
# Back up the WordPress database and content to the NAS.
#
# Runs inside a mariadb:11 container that reaches the database over the compose
# network and mounts the content volumes read-only. It deliberately does NOT
# get the docker socket: a backup job should not be able to control the host's
# containers.
set -euo pipefail

DEST="${DEST:-/backup}"
RETAIN_DAYS="${RETAIN_DAYS:-14}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"

if [ ! -d "$DEST" ]; then
  echo "ERROR: backup destination does not exist: $DEST" >&2
  exit 1
fi
if [ ! -w "$DEST" ]; then
  echo "ERROR: backup destination is not writable: $DEST" >&2
  exit 1
fi

if [ "${DRY_RUN:-0}" != "1" ]; then
  : "${WP_DB_HOST:?set WP_DB_HOST}"
  : "${WP_DB_NAME:?set WP_DB_NAME}"
  : "${WP_DB_USER:?set WP_DB_USER}"
  : "${WP_DB_PASSWORD:?set WP_DB_PASSWORD}"

  db="$DEST/db-$STAMP.sql.gz"
  content="$DEST/content-$STAMP.tar.gz"

  # --single-transaction keeps the dump consistent without locking the site.
  mariadb-dump \
    --host="$WP_DB_HOST" --user="$WP_DB_USER" --password="$WP_DB_PASSWORD" \
    --single-transaction --quick --routines --events \
    "$WP_DB_NAME" | gzip > "$db"

  tar czf "$content" -C /data uploads themes

  # A backup script that writes a corrupt archive and exits 0 is worse than no
  # backup at all, because it removes the pressure to check. Verify both.
  gzip -t "$db"
  tar tzf "$content" >/dev/null

  db_size=$(stat -c%s "$db")
  content_size=$(stat -c%s "$content")

  # A dump of a live WordPress install is never a few hundred bytes. If it is,
  # the dump failed in a way that still exited 0.
  if [ "$db_size" -lt 10240 ]; then
    echo "ERROR: database dump is only $db_size bytes, refusing to call this a backup" >&2
    rm -f "$db" "$content"
    exit 1
  fi

  echo "backup complete:"
  echo "  $(basename "$db")       $((db_size/1024)) KiB"
  echo "  $(basename "$content")  $((content_size/1024)) KiB"
fi

find "$DEST" -maxdepth 1 -type f -name '*.gz' -mtime "+$RETAIN_DAYS" -delete
echo "pruned archives older than $RETAIN_DAYS days"
