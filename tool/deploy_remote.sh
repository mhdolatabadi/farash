#!/usr/bin/env bash
# Sent over SSH from the validated CI checkout, not mutable server code.
set -euo pipefail
umask 077
repository="${1:?repository path is required}"
revision="${2:?full source commit is required}"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'A full source commit SHA is required.' >&2; exit 1; }
cd -- "$repository"
repository="$(pwd -P)"
[[ "$(git rev-parse --show-toplevel)" == "$repository" ]] || { echo 'Deployment path must be the repository root.' >&2; exit 1; }
[[ -f deploy/.env ]] || { echo 'deploy/.env is missing.' >&2; exit 1; }
grep -qE '^FARASH_DOMAIN=' deploy/.env || { echo 'deploy/.env has no FARASH_DOMAIN.' >&2; exit 1; }
git fetch --no-tags origin "$revision"
[[ "$(git rev-parse --verify "${revision}^{commit}")" == "$revision" ]]

# Keep these: running Caddy containers bind their validated config from here,
# including after Docker restarts. Never reset/stash the live checkout.
mkdir -p .farash-releases
release="$(mktemp -d "$repository/.farash-releases/${revision}.XXXXXX")"
git archive "$revision" deploy | tar -x -C "$release"
printf '%s\n' "$revision" > "$release/source-sha"
bash "$release/deploy/apply.sh" "$repository/deploy" "$revision"
