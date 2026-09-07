#!/usr/bin/env bash
# Tests publish.sh against fixtures. No network, no real git remote.
set -uo pipefail
FAILURES=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLISH="$HERE/../publish.sh"

assert() {
  if [ "$2" = "$3" ]; then echo "  PASS $1"; else
    echo "  FAIL $1: expected '$3', got '$2'"; FAILURES=$((FAILURES+1)); fi
}

setup() {
  WORK="$(mktemp -d)"
  export EXPORT_DIR="$WORK/export" REPO_DIR="$WORK/repo"
  mkdir -p "$EXPORT_DIR" "$REPO_DIR"
  ( cd "$REPO_DIR" && git init -q -b main && git config user.email t@t && git config user.name t \
    && mkdir -p site && echo old > site/index.html && git add -A && git commit -qm init )
}
teardown() { rm -rf "$WORK"; }

# A minimal valid export: index.html plus one referenced asset that exists.
valid_export() {
  mkdir -p "$EXPORT_DIR/about" "$EXPORT_DIR/wp-includes/css"
  echo '<link href="/wp-includes/css/a.css"><a href="/about/">x</a>' > "$EXPORT_DIR/index.html"
  echo '<p>about</p>' > "$EXPORT_DIR/about/index.html"
  echo 'body{}' > "$EXPORT_DIR/wp-includes/css/a.css"
}

echo "test: refuses an empty export"
setup
OUT="$(SKIP_PUSH=1 "$PUBLISH" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "explains why" "$(echo "$OUT" | grep -ci 'empty')" "1"
assert "repo untouched" "$(cat "$REPO_DIR/site/index.html")" "old"
teardown

echo "test: refuses an export with no index.html"
setup
echo x > "$EXPORT_DIR/stray.txt"
OUT="$(SKIP_PUSH=1 "$PUBLISH" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "names the missing file" "$(echo "$OUT" | grep -c 'index.html')" "1"
teardown

echo "test: refuses an export whose HTML references a missing local asset"
setup
valid_export
echo '<link href="/wp-includes/css/gone.css">' >> "$EXPORT_DIR/index.html"
OUT="$(SKIP_PUSH=1 "$PUBLISH" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "names the missing asset" "$(echo "$OUT" | grep -c 'gone.css')" "1"
assert "repo untouched" "$(cat "$REPO_DIR/site/index.html")" "old"
teardown

echo "test: bare directory references do not trip the asset check"
setup
valid_export
echo '<script>var p="/wp-content/plugins/";</script>' >> "$EXPORT_DIR/index.html"
SKIP_PUSH=1 "$PUBLISH" >/dev/null 2>&1; RC=$?
assert "exit code is 0" "$RC" "0"
teardown

echo "test: publishes a valid export"
setup
valid_export
SKIP_PUSH=1 "$PUBLISH" >/dev/null 2>&1
assert "index replaced"      "$(grep -c 'about' "$REPO_DIR/site/index.html")" "1"
assert "subdirectory copied" "$(cat "$REPO_DIR/site/about/index.html")" "<p>about</p>"
assert "asset copied"        "$(cat "$REPO_DIR/site/wp-includes/css/a.css")" "body{}"
assert "commit created"      "$(cd "$REPO_DIR" && git log --oneline | wc -l | tr -d ' ')" "2"
teardown

echo "test: removes files deleted in WordPress"
setup
( cd "$REPO_DIR" && mkdir -p site/gone && echo x > site/gone/index.html && git add -A && git commit -qm stale )
valid_export
SKIP_PUSH=1 "$PUBLISH" >/dev/null 2>&1
assert "stale path removed" "$([ -e "$REPO_DIR/site/gone" ] && echo present || echo absent)" "absent"
teardown

echo "test: no commit when nothing changed"
setup
valid_export
SKIP_PUSH=1 "$PUBLISH" >/dev/null 2>&1
BEFORE="$(cd "$REPO_DIR" && git log --oneline | wc -l | tr -d ' ')"
SKIP_PUSH=1 "$PUBLISH" >/dev/null 2>&1
assert "no empty second commit" "$(cd "$REPO_DIR" && git log --oneline | wc -l | tr -d ' ')" "$BEFORE"
teardown

echo
[ "$FAILURES" -eq 0 ] && echo "ALL TESTS PASSED" || { echo "$FAILURES FAILURE(S)"; exit 1; }
