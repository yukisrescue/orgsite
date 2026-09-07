#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f .env ] || { echo "ERROR: .env missing. Copy .env.example and fill it in." >&2; exit 1; }
docker compose up -d
echo "WordPress stack up."
