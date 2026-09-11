#!/usr/bin/env bash
# Sync a Simply Static export into the orgsite repo and push.
# Pushing triggers .github/workflows/deploy.yml, which deploys to Cloudflare.
set -euo pipefail

EXPORT_DIR="${EXPORT_DIR:?set EXPORT_DIR}"
REPO_DIR="${REPO_DIR:?set REPO_DIR}"
BRANCH="${BRANCH:-main}"

# --- Guard 1: the export exists and is not empty ----------------------------
# rsync --delete below is destructive. A failed or half-run export must never
# reach it, or production is blanked.
if [ ! -d "$EXPORT_DIR" ] || [ -z "$(ls -A "$EXPORT_DIR" 2>/dev/null)" ]; then
  echo "ERROR: export directory is empty, refusing to publish: $EXPORT_DIR" >&2
  exit 1
fi

if [ ! -f "$EXPORT_DIR/index.html" ]; then
  echo "ERROR: export has no index.html, refusing to publish an incomplete export" >&2
  exit 1
fi

# --- Guard 2: every referenced local asset was actually exported ------------
# Simply Static discovers assets by parsing markup, so anything WordPress emits
# through JSON or generated markup is invisible to it and silently 404s in
# production. This has bitten us twice (the emoji polyfill, and the block
# template skip-link stylesheet). Catch it here rather than in front of visitors.
missing=""
while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    */) continue ;;                      # directory prefix from JS config
  esac
  # Only paths that look like files (a dot in the last segment).
  case "${path##*/}" in
    *.*) ;;
    *) continue ;;
  esac
  [ -f "$EXPORT_DIR$path" ] || missing="$missing $path"
done <<EOF
$(find "$EXPORT_DIR" -type f \( -name '*.html' -o -name '*.css' \) -print0 \
   | xargs -0 cat 2>/dev/null \
   | sed 's|\\/|/|g' \
   | grep -oE '/wp-(includes|content)/[A-Za-z0-9_./-]+' \
   | sed 's/?.*//' \
   | sort -u)
EOF

if [ -n "$missing" ]; then
  echo "ERROR: exported HTML references files that are not in the export:" >&2
  for m in $missing; do echo "  $m" >&2; done
  echo "These would 404 in production. Add them to additional_urls in" >&2
  echo "ss-configure.php, or remove the reference at source." >&2
  exit 1
fi

# --- Publish ----------------------------------------------------------------
cd "$REPO_DIR"

# Prove git is usable BEFORE relying on its output. A git failure here used to
# surface as empty `git status` output, which the change check below read as
# "nothing to publish" -- so a broken audit trail looked like a successful
# no-op run. Assert instead of inferring.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: $REPO_DIR is not a usable git repository" >&2
  { git rev-parse --git-dir 2>&1 || true; } | sed 's/^/  /' >&2
  exit 1
fi

mkdir -p site

# --delete so pages removed in WordPress disappear from production.
rsync -a --delete "$EXPORT_DIR"/ site/

if ! status="$(git status --porcelain site/ 2>&1)"; then
  echo "ERROR: git status failed, refusing to guess whether anything changed" >&2
  echo "$status" | sed 's/^/  /' >&2
  exit 1
fi

if [ -z "$status" ]; then
  echo "no changes to publish"
  exit 0
fi

git add site/
git -c user.email="wordpress@yukisrescue.org" \
    -c user.name="Yuki's Rescue WordPress" \
    commit -q -m "publish: static export $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "${SKIP_PUSH:-0}" = "1" ]; then
  echo "published locally (push skipped)"
  exit 0
fi

# Humans commit docs and configuration from elsewhere while this publishes
# site/, so the branches diverge routinely. Rebase onto the remote before
# pushing rather than failing every time someone else committed.
if git fetch -q origin "$BRANCH" 2>/dev/null; then
  if ! git rebase -q "origin/$BRANCH" 2>&1; then
    echo "WARNING: rebase onto origin/$BRANCH failed; aborting rebase" >&2
    git rebase --abort 2>/dev/null || true
  fi
fi

# Best-effort. The commit above is the durable audit record and it has already
# been made; GitHub is an offsite copy, not the critical path. A push failure
# must not stop the site from being published, but it must be loud, because a
# run of them means the audit trail is drifting from what is deployed.
if git push origin "$BRANCH" 2>&1; then
  echo "published and pushed"
else
  echo "WARNING: commit succeeded but push to origin/$BRANCH FAILED." >&2
  echo "         The audit trail is local-only until this is resolved." >&2
fi
