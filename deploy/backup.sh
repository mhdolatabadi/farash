#!/usr/bin/env bash
# Creates and validates one private custom-format database snapshot.
set -euo pipefail
umask 077
cd "$(dirname "$0")"
source ./compose-command.sh
backup_root="${FARASH_BACKUP_DIR:-$PWD/backups}"
mkdir -p "$backup_root"
backup_tmp="$(mktemp "$backup_root/.pending.XXXXXX")"
trap 'rm -f "$backup_tmp"' EXIT
farash_compose exec -T postgres pg_dump -U farash -d farash --format=custom > "$backup_tmp"
farash_compose exec -T postgres pg_restore --list < "$backup_tmp" > /dev/null
backup_path="$backup_root/farash-$(date -u +%Y%m%dT%H%M%SZ)-$$.dump"
mv "$backup_tmp" "$backup_path"
trap - EXIT
sha256sum "$backup_path" > "$backup_path.sha256"
printf 'Database backup created: %s\n' "$backup_path"
