#!/usr/bin/env bash
# Read-only inventory of WordPress plugin files in Docker volumes.
# Run on the Docker host. This does not alter WordPress or any volume.
set -euo pipefail

command -v docker >/dev/null || { echo 'docker is required' >&2; exit 1; }

echo 'Current WordPress mounts:'
docker inspect --format '{{range .Mounts}}{{println .Destination .Name .Type}}{{end}}' yukis-wordpress
echo
echo 'Plugins in current container:'
docker exec yukis-wordpress sh -c 'ls -1 /var/www/html/wp-content/plugins'
echo
echo 'Detached Docker volumes containing WordPress plugin directories:'

count=0
while IFS= read -r volume; do
  [ -n "$volume" ] || continue
  plugins="$(docker run --rm --network none \
    --mount "type=volume,source=$volume,target=/candidate,readonly" \
    alpine:3.20 sh -c \
    'if [ -d /candidate/wp-content/plugins ]; then ls -1 /candidate/wp-content/plugins; fi')"
  [ -n "$plugins" ] || continue
  count=$((count + 1))
  created="$(docker volume inspect --format '{{.CreatedAt}}' "$volume")"
  echo
  echo "volume=$volume created=$created"
  echo "$plugins" | sed 's/^/  /'
done < <(docker volume ls -q --filter dangling=true)

if [ "$count" -eq 0 ]; then
  echo 'No detached WordPress plugin volume found.'
fi
