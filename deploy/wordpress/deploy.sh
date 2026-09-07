#!/usr/bin/env bash
# Deploy site/ to Cloudflare Workers.
#
# GitHub Actions is disabled account-wide on the repository owner, so the
# deploy runs here instead of in CI. .github/workflows/deploy.yml is retained
# and does the same thing; when Actions is restored, stop calling this script
# and the workflow takes over unchanged.
set -euo pipefail

REPO_DIR="${REPO_DIR:?set REPO_DIR}"
: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?set CLOUDFLARE_ACCOUNT_ID}"
VERIFY_URL="${VERIFY_URL:-https://www.yukisrescue.org/}"
VERIFY_MARKER="${VERIFY_MARKER:-Yuki}"

cd "$REPO_DIR"

# Same guard the workflow applies. publish.sh has already checked the export,
# but this runs against what is actually on disk about to be uploaded.
if [ ! -f site/index.html ]; then
  echo "ERROR: site/index.html missing, refusing to deploy" >&2
  exit 1
fi
count="$(find site -type f | wc -l | tr -d ' ')"
if [ "$count" -lt 4 ]; then
  echo "ERROR: only $count files under site/, implausibly small, refusing to deploy" >&2
  exit 1
fi
echo "deploy: $count files"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

wrangler versions upload 2>&1 | tee "$log"

version_id="$(grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$log" | head -1)"
if [ -z "$version_id" ]; then
  echo "ERROR: could not determine version id from upload output" >&2
  exit 1
fi
echo "deploy: uploaded version $version_id"

wrangler versions deploy "${version_id}@100%" --yes

# Confirm production actually serves the new build. A deploy that reports
# success but leaves stale content is the failure mode worth catching.
sleep 5
code="$(curl -sS -o /tmp/deployed.html -w '%{http_code}' "$VERIFY_URL" || echo 000)"
if [ "$code" != "200" ]; then
  echo "WARNING: $VERIFY_URL returned $code after deploy" >&2
  exit 1
fi
if ! grep -q "$VERIFY_MARKER" /tmp/deployed.html; then
  echo "WARNING: deployed page does not contain '$VERIFY_MARKER'" >&2
  exit 1
fi
echo "deploy: verified live at $VERIFY_URL (version $version_id)"
