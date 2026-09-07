#!/usr/bin/env bash
set -euo pipefail
wp() { docker exec -u www-data yukis-wordpress wp "$@"; }

SEED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/seed"

page_id() { wp post list --post_type=page --name="$1" --field=ID | head -1 | tr -d '\r'; }

create_page() {
  local slug="$1" title="$2" file="$3"
  local existing; existing="$(page_id "$slug")"
  if [ -n "$existing" ]; then
    docker exec -i -u www-data yukis-wordpress wp post update "$existing" \
      --post_title="$title" - < "$file"
    echo "updated $slug (id $existing)"
  else
    docker exec -i -u www-data yukis-wordpress wp post create \
      --post_type=page --post_status=publish --post_name="$slug" --post_title="$title" - < "$file"
    echo "created $slug"
  fi
}

create_page about    "About Us"                       "$SEED_DIR/placeholder.html"
create_page rescue   "Rescue a Dog"                   "$SEED_DIR/placeholder.html"
create_page feedback "Feedback"                       "$SEED_DIR/placeholder.html"
create_page home     "Saving Lives, One Paw at a Time" "$SEED_DIR/home.html"

HOME_ID="$(page_id home)"
wp option update show_on_front page
wp option update page_on_front "$HOME_ID"

echo "content seed complete (front page id $HOME_ID)"
