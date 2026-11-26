#!/usr/bin/env bash
# Populate the destination cache before its immutable runner changes containers.
set -euo pipefail
: "${DEPLOY_HOST:?DEPLOY_HOST is required}"
: "${DEPLOY_USER:?DEPLOY_USER is required}"
: "${DEPLOY_SHA:?DEPLOY_SHA is required}"
[[ "$DEPLOY_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo 'A full commit SHA is required.' >&2; exit 1; }
image_repo="${FARASH_IMAGE_REPO:-ghcr.io/mhdolatabadi/farash}"
images=("$image_repo/api:$DEPLOY_SHA" "$image_repo/web:$DEPLOY_SHA")
ssh_options=(-i "${DEPLOY_IDENTITY_FILE:-$HOME/.ssh/id_deploy}"
  -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes
  -o ConnectTimeout=20 -o ServerAliveInterval=15 -o ServerAliveCountMax=4
  -p "${DEPLOY_PORT:-22}")
destination="$DEPLOY_USER@$DEPLOY_HOST"
platform="$(ssh "${ssh_options[@]}" "$destination" "docker version --format '{{.Server.Os}}/{{.Server.Arch}}'")"
[[ "$platform" =~ ^linux/(amd64|arm64)$ ]] || { echo 'Unsupported deployment platform.' >&2; exit 1; }

# Complete both pulls before sending anything. A failed transfer only changes
# the image cache; the database backup and rollout remain in deploy/apply.sh.
for image in "${images[@]}"; do
  docker pull --platform "$platform" "$image"
done
docker image save "${images[@]}" | gzip -1 | \
  ssh "${ssh_options[@]}" "$destination" "bash -o pipefail -c 'gzip -d | docker image load'"
