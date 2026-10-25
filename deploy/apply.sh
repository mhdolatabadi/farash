#!/usr/bin/env bash
# Applies exported source using the existing private configuration.
set -euo pipefail
config_dir="${1:?configuration directory is required}"
revision="${2:?full source commit is required}"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || exit 1
cd -- "$(dirname "$0")"
source_dir="$(pwd -P)"
config_dir="$(cd -- "$config_dir" && pwd -P)"
[[ -f "$config_dir/.env" ]] || { echo 'Deployment configuration is missing.' >&2; exit 1; }
grep -qE '^FARASH_DOMAIN=' "$config_dir/.env" || { echo 'FARASH_DOMAIN is missing.' >&2; exit 1; }
export FARASH_DEPLOY_CONFIG_DIR="$config_dir"
export FARASH_IMAGE_TAG="$revision"
export FARASH_CADDYFILE="$source_dir/Caddyfile"
export FARASH_BACKUP_DIR="${FARASH_BACKUP_DIR:-$config_dir/backups}"
source ./compose-command.sh
farash_compose pull api web
farash_compose up -d --no-deps --wait postgres
bash ./backup.sh
farash_compose up -d --no-build --remove-orphans
docker image prune -f
domain="$(grep -E '^FARASH_DOMAIN=' "$config_dir/.env" | cut -d= -f2-)"
for attempt in $(seq 1 30); do
  if curl -fsS "https://${domain}/api/v1/health"; then
    echo
    echo "Deployed $revision to https://${domain}"
    exit 0
  fi
  sleep 5
done
echo "Health check failed for https://${domain}/api/v1/health" >&2
farash_compose ps
farash_compose logs --tail=100 api
exit 1
