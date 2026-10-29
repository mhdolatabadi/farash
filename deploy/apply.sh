#!/usr/bin/env bash
# Applies exported source using the existing private configuration.
set -euo pipefail
config_dir="${1:?configuration directory is required}"
revision="${2:?full source commit is required}"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || exit 1
cd -- "$(dirname "$0")"
config_dir="$(cd -- "$config_dir" && pwd -P)"
[[ -f "$config_dir/.env" ]] || { echo 'Deployment configuration is missing.' >&2; exit 1; }
grep -qE '^FARASH_DOMAIN=' "$config_dir/.env" || { echo 'FARASH_DOMAIN is missing.' >&2; exit 1; }
proxy_network="$(grep -E '^FARASH_PROXY_NETWORK=' "$config_dir/.env" | tail -n 1 | cut -d= -f2- || true)"
proxy_network="${proxy_network:-proxynet}"
docker network inspect "$proxy_network" >/dev/null 2>&1 || {
  echo "Shared proxy network '$proxy_network' is missing." >&2
  exit 1
}

export FARASH_DEPLOY_CONFIG_DIR="$config_dir"
export FARASH_IMAGE_TAG="$revision"
export FARASH_BACKUP_DIR="${FARASH_BACKUP_DIR:-$config_dir/backups}"
source ./compose-command.sh

# Pull both immutable application images before changing running containers.
farash_compose pull api web
farash_compose up -d --no-deps --wait postgres
bash ./backup.sh
# This also removes the obsolete Farash Caddy container from deployments that
# predate the shared-proxy integration. It never touches the external proxy.
farash_compose up -d --no-build --remove-orphans
docker image prune -f

domain="$(grep -E '^FARASH_DOMAIN=' "$config_dir/.env" | cut -d= -f2-)"
for attempt in $(seq 1 30); do
  if curl --connect-timeout 5 --max-time 15 -fsS "https://${domain}/api/v1/health"; then
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
