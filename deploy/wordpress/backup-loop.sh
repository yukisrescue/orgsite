#!/usr/bin/env bash
# Runs backup.sh once per day at BACKUP_HOUR UTC.
# A container loop rather than a systemd timer: node2 has no passwordless sudo,
# and this moves with the stack to a VPS where host units would not.
set -uo pipefail
BACKUP_HOUR="${BACKUP_HOUR:-3}"
BACKUP_MIN="${BACKUP_MIN:-30}"

echo "backup: scheduled daily at ${BACKUP_HOUR}:${BACKUP_MIN} UTC"
while true; do
  now_h=$(date -u +%H); now_m=$(date -u +%M)
  # Seconds until the next occurrence of the target time.
  target=$(( (10#$BACKUP_HOUR * 3600) + (10#$BACKUP_MIN * 60) ))
  current=$(( (10#$now_h * 3600) + (10#$now_m * 60) ))
  wait=$(( target - current ))
  [ "$wait" -le 0 ] && wait=$(( wait + 86400 ))
  echo "backup: sleeping ${wait}s until next run"
  sleep "$wait"
  echo "backup: starting $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  /backup.sh || echo "backup: FAILED" >&2
done
