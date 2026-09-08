#!/usr/bin/env bash
# Tests backup.sh guard and retention logic against fixtures. No database.
set -uo pipefail
FAILURES=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HERE/../backup.sh"

assert() {
  if [ "$2" = "$3" ]; then echo "  PASS $1"; else
    echo "  FAIL $1: expected '$3', got '$2'"; FAILURES=$((FAILURES+1)); fi
}

echo "test: fails when the destination does not exist"
OUT="$(DEST=/nonexistent/path DRY_RUN=1 "$BACKUP" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "says destination"  "$(echo "$OUT" | grep -ci 'destination')" "1"

echo "test: fails when the destination is not writable"
W="$(mktemp -d)"; chmod 500 "$W"
OUT="$(DEST=$W DRY_RUN=1 "$BACKUP" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "says not writable" "$(echo "$OUT" | grep -ci 'not writable')" "1"
chmod 700 "$W"; rm -rf "$W"

echo "test: prunes archives older than the retention window, keeps recent"
W="$(mktemp -d)"
touch -t "$(date -v-30d +%Y%m%d0000 2>/dev/null || date -d '30 days ago' +%Y%m%d0000)" "$W/db-old.sql.gz"
touch "$W/db-recent.sql.gz"
DEST="$W" RETAIN_DAYS=14 DRY_RUN=1 "$BACKUP" >/dev/null 2>&1
assert "old archive pruned"  "$([ -e "$W/db-old.sql.gz" ] && echo present || echo absent)" "absent"
assert "recent archive kept" "$([ -e "$W/db-recent.sql.gz" ] && echo present || echo absent)" "present"
rm -rf "$W"

echo "test: leaves non-archive files alone"
W="$(mktemp -d)"
touch -t "$(date -v-30d +%Y%m%d0000 2>/dev/null || date -d '30 days ago' +%Y%m%d0000)" "$W/README.txt"
DEST="$W" RETAIN_DAYS=14 DRY_RUN=1 "$BACKUP" >/dev/null 2>&1
assert "non-archive untouched" "$([ -e "$W/README.txt" ] && echo present || echo absent)" "present"
rm -rf "$W"

echo
[ "$FAILURES" -eq 0 ] && echo "ALL TESTS PASSED" || { echo "$FAILURES FAILURE(S)"; exit 1; }
