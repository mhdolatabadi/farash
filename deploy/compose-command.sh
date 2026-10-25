#!/usr/bin/env bash
# Every operation addresses the same stable Compose project and private config.
farash_compose() {
  if [[ -n "${FARASH_DEPLOY_CONFIG_DIR:-}" ]]; then
    local compose_dir
    compose_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    docker compose --project-directory "$FARASH_DEPLOY_CONFIG_DIR" \
      --env-file "$FARASH_DEPLOY_CONFIG_DIR/.env" \
      -f "$compose_dir/compose.yaml" "$@"
  else
    docker compose "$@"
  fi
}
