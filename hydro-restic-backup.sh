#!/usr/bin/env bash

set -euo pipefail
trap 'echo "========== $(date "+%F %T") Backup failed (exit code: $?) =========="' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/hydro-restic-backup.env"

if [[ -f "$ENV_FILE" ]]; then
    . "$ENV_FILE"
fi

for required_var in RESTIC_REPOSITORY RESTIC_PASSWORD; do
    if [[ -z "${!required_var:-}" ]]; then
        echo "Missing required variable: $required_var (set it in environment or $ENV_FILE)"
        exit 1
    fi
done

if ! command -v hydrooj >/dev/null 2>&1 || ! command -v restic >/dev/null 2>&1; then
    export HOME=/root
    export USER=root
    . /root/.nix-profile/etc/profile.d/nix.sh
fi

echo
echo "========== $(date '+%F %T') Backup started =========="

hydrooj backup \
    -r "$RESTIC_REPOSITORY" \
    -p "$RESTIC_PASSWORD"

echo "========== $(date '+%F %T') Backup finished =========="
echo