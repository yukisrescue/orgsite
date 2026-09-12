#!/usr/bin/env bash
# Tests rollback-last-publish.sh against a disposable linear publish history.
set -uo pipefail

FAILURES=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLLBACK="$HERE/../rollback-last-publish.sh"

assert() {
  if [ "$2" = "$3" ]; then echo "  PASS $1"; else
    echo "  FAIL $1: expected '$3', got '$2'"; FAILURES=$((FAILURES+1)); fi
}

setup() {
  WORK="$(mktemp -d)"
  REPO="$WORK/repo"
  mkdir -p "$REPO"
  ( cd "$REPO" && git init -q -b main && git config user.email t@t && git config user.name t \
    && mkdir -p site && echo old > site/index.html && git add -A && git commit -qm init \
    && echo one > site/index.html && git add -A && git commit -qm 'publish: static export one' \
    && echo two > site/index.html && git add -A && git commit -qm 'publish: static export two' \
    && echo three > site/index.html && git add -A && git commit -qm 'publish: static export three' )
  PUBLISH_THREE="$(cd "$REPO" && git rev-parse HEAD)"
  PUBLISH_TWO="$(cd "$REPO" && git rev-parse HEAD^ )"
  PUBLISH_ONE="$(cd "$REPO" && git rev-parse HEAD^^ )"
  ( cd "$REPO" && git revert --no-edit "$PUBLISH_THREE" >/dev/null )
}
teardown() { rm -rf "$WORK"; }

echo "test: repeated no-argument runs walk to each older publish"
setup
OUT="$(ROLLBACK_REPO_DIR="$REPO" SKIP_DEPLOY=1 SKIP_PUSH=1 "$ROLLBACK" 2>&1)"; RC=$?
assert "first rollback succeeds" "$RC" "0"
assert "first rollback reaches publish one" "$(cat "$REPO/site/index.html")" "one"
assert "first rollback records source" "$(echo "$OUT" | grep -c -- ' -> ')" "1"
( cd "$REPO" && echo note > operator-note.txt && git add operator-note.txt && git commit -qm 'docs: operator note' )
OUT="$(ROLLBACK_REPO_DIR="$REPO" SKIP_DEPLOY=1 SKIP_PUSH=1 "$ROLLBACK" 2>&1)"; RC=$?
assert "second rollback succeeds" "$RC" "0"
assert "second rollback reaches initial state" "$(cat "$REPO/site/index.html")" "old"
assert "two rollback commits exist" "$(cd "$REPO" && git log --format='%s' | grep -c '^rollback:')" "2"
teardown

echo "test: explicit SHA restores that commit's site tree"
setup
OUT="$(ROLLBACK_REPO_DIR="$REPO" SKIP_DEPLOY=1 SKIP_PUSH=1 "$ROLLBACK" "$PUBLISH_TWO" 2>&1)"; RC=$?
assert "SHA rollback succeeds" "$RC" "0"
assert "SHA target restored" "$(cat "$REPO/site/index.html")" "two"
teardown

echo "test: dirty repository is refused"
setup
echo dirty > "$REPO/unrelated.txt"
OUT="$(ROLLBACK_REPO_DIR="$REPO" SKIP_DEPLOY=1 SKIP_PUSH=1 "$ROLLBACK" 2>&1)"; RC=$?
assert "dirty rollback fails" "$RC" "1"
assert "explains dirty state" "$(echo "$OUT" | grep -ci 'clean')" "1"
teardown

echo "test: invalid SHA is refused"
setup
OUT="$(ROLLBACK_REPO_DIR="$REPO" SKIP_DEPLOY=1 SKIP_PUSH=1 "$ROLLBACK" not-a-commit 2>&1)"; RC=$?
assert "invalid SHA fails" "$RC" "1"
assert "explains invalid SHA" "$(echo "$OUT" | grep -ci 'commit')" "1"
teardown

echo
[ "$FAILURES" -eq 0 ] && echo "ALL TESTS PASSED" || { echo "$FAILURES FAILURE(S)"; exit 1; }
