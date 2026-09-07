#!/usr/bin/env bash
# Publishes when the export directory has changed and has settled.
#
# Runs as a container in the compose stack rather than a systemd timer:
# installing units needs sudo, which is not available passwordless on node2,
# and a container moves with the stack to a VPS where host units would not.
set -uo pipefail

EXPORT_DIR="${EXPORT_DIR:-/export/out}"
REPO_DIR="${REPO_DIR:-/repo}"
STATE_FILE="${STATE_FILE:-/state/last-export-hash}"
INTERVAL="${INTERVAL:-30}"
SETTLE_SECONDS="${SETTLE_SECONDS:-20}"

mkdir -p "$(dirname "$STATE_FILE")"
echo "publisher: watching $EXPORT_DIR every ${INTERVAL}s (settle ${SETTLE_SECONDS}s)"

while true; do
  sleep "$INTERVAL"

  [ -d "$EXPORT_DIR" ] || continue

  newest="$(find "$EXPORT_DIR" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)"
  [ -n "$newest" ] || continue

  # Simply Static writes many files over several seconds. Publishing mid-write
  # would push a half-exported site, so wait for the tree to stop changing.
  now="$(date +%s)"
  if [ $((now - newest)) -lt "$SETTLE_SECONDS" ]; then
    echo "publisher: export still settling, deferring"
    continue
  fi

  hash="$(find "$EXPORT_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort | sha256sum | cut -d' ' -f1)"
  prev="$(cat "$STATE_FILE" 2>/dev/null || echo none)"
  [ "$hash" = "$prev" ] && continue

  echo "publisher: new export detected, publishing"
  if ! EXPORT_DIR="$EXPORT_DIR" REPO_DIR="$REPO_DIR" /publish.sh; then
    echo "publisher: publish FAILED, will retry next tick" >&2
    continue
  fi

  if REPO_DIR="$REPO_DIR" /deploy.sh; then
    # Record the hash only after a verified deploy, so a failure is retried
    # rather than silently skipped until the next content change.
    echo "$hash" > "$STATE_FILE"
    echo "publisher: published and deployed"
  else
    echo "publisher: deploy FAILED, will retry next tick" >&2
  fi
done
