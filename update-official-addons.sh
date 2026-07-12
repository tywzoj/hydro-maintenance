#!/bin/bash

PUBLIC_ADDON_HYDRO_CLIENT_URL="https://hydro.ac/hydroac-client.zip"

###################### CONFIGURATION END ######################

set -euo pipefail
trap 'echo "========== $(date "+%F %T") Addons update failed (exit code: $?) =========="' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/update-official-addons.env"

if [[ -f "$ENV_FILE" ]]; then
	. "$ENV_FILE"
fi

if ! command -v hydrooj >/dev/null 2>&1; then
	export HOME=/root
	export USER=root
	. /root/.nix-profile/etc/profile.d/nix.sh
fi

echo
echo "========== $(date '+%F %T') Addons update started =========="

hydrooj install "$PUBLIC_ADDON_HYDRO_CLIENT_URL"

if [[ -n "${PRIVATE_ADDON_URL:-}" ]]; then
	hydrooj install "$PRIVATE_ADDON_URL"
else
	echo "Skip private addons: PRIVATE_ADDON_URL is not set"
fi

echo "========== $(date '+%F %T') Addons update finished =========="
echo