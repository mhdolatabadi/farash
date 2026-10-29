#!/usr/bin/env bash
# Manual entry point; CI sends its validated bootstrap directly over SSH.
set -euo pipefail
repository="$(cd -- "$(dirname "$0")/.." && pwd -P)"
exec bash "$repository/tool/deploy_remote.sh" "$repository" "${1:?full source commit is required}"
