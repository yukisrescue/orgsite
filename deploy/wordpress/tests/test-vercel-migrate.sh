#!/usr/bin/env bash
set -uo pipefail
FAILURES=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATE="$HERE/../vercel_migrate_home.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert() {
  if [ "$2" = "$3" ]; then echo "  PASS $1"
  else echo "  FAIL $1: expected '$3', got '$2'"; FAILURES=$((FAILURES+1)); fi
}

cat > "$WORK/wp" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WP_LOG"
case "$1 $2" in
  'theme is-active') [ "${WP_MODE:-ok}" != inactive ] ;;
  'option get') echo 11 ;;
  'eval '*)
    [ "${WP_MODE:-ok}" != missing ] || { echo 'missing pattern' >&2; exit 1; }
    printf '%s' '<!-- wp:group --><div class="wp-block-group vercel_section">source</div><!-- /wp:group -->'
    ;;
  'post update') cat >> "$WP_STDIN" ;;
  'option update') : ;;
esac
FAKE
chmod +x "$WORK/wp"
export WP_RUNNER="$WORK/wp" WP_LOG="$WORK/log" WP_STDIN="$WORK/stdin"

echo 'test: explicit apply guard'
: > "$WP_LOG"
OUT="$("$MIGRATE" 2>&1)"; RC=$?
assert 'exit 1' "$RC" 1
assert 'no update' "$(grep -c 'post update' "$WP_LOG")" 0

echo 'test: active theme required'
: > "$WP_LOG"
OUT="$(WP_MODE=inactive APPLY=1 "$MIGRATE" 2>&1)"; RC=$?
assert 'exit 1' "$RC" 1
assert 'names theme' "$(echo "$OUT" | grep -ci yukis)" 1

echo 'test: registered pattern required'
: > "$WP_LOG"
OUT="$(WP_MODE=missing APPLY=1 "$MIGRATE" 2>&1)"; RC=$?
assert 'exit 1' "$RC" 1
assert 'no update' "$(grep -c 'post update' "$WP_LOG")" 0

echo 'test: updates configured front page from pattern'
: > "$WP_LOG"; : > "$WP_STDIN"
APPLY=1 "$MIGRATE" >/dev/null 2>&1; RC=$?
assert 'exit 0' "$RC" 0
assert 'updates page 11' "$(grep -c 'post update 11' "$WP_LOG")" 1
assert 'keeps front page' "$(grep -c 'option update page_on_front 11' "$WP_LOG")" 1
assert 'pipes pattern' "$(grep -c 'vercel_section' "$WP_STDIN")" 1

echo 'test: fresh seed delegates Home to guarded migration'
SEED="$HERE/../wp-content-seed.sh"
assert 'calls migration' "$(grep -c 'vercel_migrate_home.sh' "$SEED")" 1
assert 'does not use obsolete Home seed' "$(grep -c 'seed/home.html' "$SEED")" 0
assert 'passes pattern content to Docker WP-CLI' "$(grep -c 'docker exec -i' "$MIGRATE")" 1

echo
[ "$FAILURES" -eq 0 ] && echo 'ALL TESTS PASSED' || {
  echo "$FAILURES FAILURE(S)"; exit 1;
}
