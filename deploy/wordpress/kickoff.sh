#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f .env ] || { echo "ERROR: .env missing. Copy .env.example and fill it in." >&2; exit 1; }

docker compose up -d

# Named volumes mount empty and root-owned over wp-content paths, which makes
# media uploads fail with "Unable to create directory". The themes volume
# inherits ownership from the image because it is populated on first mount;
# uploads starts empty and does not. Fixing it here keeps a rebuild on fresh
# volumes (a VPS move) from reintroducing the problem.
docker exec yukis-wordpress chown -R www-data:www-data \
  /var/www/html/wp-content/uploads \
  /var/www/html/wp-content/themes

echo "WordPress stack up."
