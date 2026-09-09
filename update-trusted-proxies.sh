#!/bin/bash

set -euo pipefail
trap 'echo "========== $(date "+%F %T") Trusted proxies update failed (exit code: $?) =========="' ERR

log() {
	echo "[$(date '+%F %T')] $*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/update-trusted-proxies.env"

if [[ -f "$ENV_FILE" ]]; then
	. "$ENV_FILE"
fi

CADDYFILE="${CADDYFILE:-/root/.hydro/Caddyfile}"
REGION="${REGION:-cn-hangzhou}"
DEBUG="${DEBUG:-false}"

if [[ -z "${SITE_ID:-}" ]]; then
	echo "Missing required variable: SITE_ID (set it in environment or $ENV_FILE)" >&2
	exit 1
fi

case "$DEBUG" in
	true)
		TARGET_CADDYFILE="${CADDYFILE}.debug"
		;;
	false)
		TARGET_CADDYFILE="$CADDYFILE"
		;;
	*)
		echo "DEBUG must be true or false" >&2
		exit 1
		;;
esac

if ! command -v pm2 >/dev/null 2>&1; then
	export HOME=/root
	export USER=root
	. /root/.nix-profile/etc/profile.d/nix.sh
fi

for command in aliyun jq awk mktemp cp mv pm2; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "Required command not found: $command" >&2
		exit 1
	fi
done

if [[ ! -f "$CADDYFILE" ]]; then
	echo "Caddyfile not found: $CADDYFILE" >&2
	exit 1
fi

if [[ "$DEBUG" == true ]]; then
	cp -p -- "$CADDYFILE" "$TARGET_CADDYFILE"
fi

echo
echo "========== $(date '+%F %T') Trusted proxies update started =========="

log "Requesting Alibaba Cloud ESA IP whitelist update"
aliyun esa update-origin-protection-ip-white-list \
	--region "$REGION" \
	--site-id "$SITE_ID" >/dev/null

log "Retrieving current Alibaba Cloud ESA IP whitelist"
WHITELIST_JSON="$(aliyun esa get-origin-protection \
	--region "$REGION" \
	--site-id "$SITE_ID")"

if ! TRUSTED_PROXY_LIST="$(jq -er '
	.CurrentIPWhitelist
	| ((.IPv4 // []) + (.IPv6 // []))
	| select(length > 0 and all(.[]; type == "string"))
	| join(" ")
' <<< "$WHITELIST_JSON")"; then
	echo "Aliyun ESA returned an invalid or empty IP whitelist" >&2
	exit 1
fi

if [[ ! "$TRUSTED_PROXY_LIST" =~ ^[0-9A-Fa-f:./]+([[:space:]][0-9A-Fa-f:./]+)*$ ]]; then
	echo "Aliyun ESA returned an unsafe IP whitelist" >&2
	exit 1
fi

read -r -a TRUSTED_PROXIES <<< "$TRUSTED_PROXY_LIST"
log "Retrieved ${#TRUSTED_PROXIES[@]} trusted proxy IP ranges"

TEMP_FILE="$(mktemp "${TARGET_CADDYFILE}.tmp.XXXXXX")"
trap 'rm -f -- "$TEMP_FILE"' EXIT
cp -p -- "$TARGET_CADDYFILE" "$TEMP_FILE"

if ! awk -v proxies="$TRUSTED_PROXY_LIST" '
function comment_at(line,    i, char, quote, escaped) {
	for (i = 1; i <= length(line); i++) {
		char = substr(line, i, 1)
		if (escaped) {
			escaped = 0
		} else if (char == "\\" && quote == "\"") {
			escaped = 1
		} else if (quote != "") {
			if (char == quote)
				quote = ""
		} else if (char == "\"" || char == "`") {
			quote = char
		} else if (char == "#") {
			return i
		}
	}
	return 0
}

function brace_delta(line,    i, char, quote, escaped, delta) {
	for (i = 1; i <= length(line); i++) {
		char = substr(line, i, 1)
		if (escaped) {
			escaped = 0
		} else if (char == "\\" && quote == "\"") {
			escaped = 1
		} else if (quote != "") {
			if (char == quote)
				quote = ""
		} else if (char == "\"" || char == "`") {
			quote = char
		} else if (char == "#") {
			break
		} else if (char == "{") {
			delta++
		} else if (char == "}") {
			delta--
		}
	}
	return delta
}

{
	raw = $0
	comment_position = comment_at(raw)
	if (comment_position) {
		body = substr(raw, 1, comment_position - 1)
		comment = substr(raw, comment_position)
	} else {
		body = raw
		comment = ""
	}

	candidate = body
	sub(/^[[:space:]]+/, "", candidate)
	sub(/[[:space:]]+$/, "", candidate)

	if (!server_depth && candidate ~ /^servers([[:space:]]+[^{}]+)?[[:space:]]*\{$/)
		server_depth = depth + 1

	if (server_depth && candidate ~ /^trusted_proxies[[:space:]]+static([[:space:]]+.*)?$/) {
		match(body, /^[[:space:]]*/)
		indent = substr(body, 1, RLENGTH)
		without_trailing_space = body
		sub(/[[:space:]]+$/, "", without_trailing_space)
		trailing_space = substr(body, length(without_trailing_space) + 1)
		if (comment != "" && trailing_space == "")
			trailing_space = " "
		print indent "trusted_proxies static " proxies trailing_space comment
		replacements++
	} else {
		print raw
	}

	depth += brace_delta(raw)
	if (server_depth && depth < server_depth)
		server_depth = 0
}

END {
	if (!replacements)
		exit 1
}
' "$TARGET_CADDYFILE" > "$TEMP_FILE"; then
	echo "No trusted_proxies static directive found in a servers block" >&2
	exit 1
fi

mv -- "$TEMP_FILE" "$TARGET_CADDYFILE"
trap - EXIT

log "Updated trusted proxies in $TARGET_CADDYFILE"

if pm2 restart caddy >/dev/null 2>&1; then
	log "Caddy restart succeeded"
else
	log "Caddy restart failed"
	exit 1
fi

echo "========== $(date '+%F %T') Trusted proxies update finished =========="
echo
