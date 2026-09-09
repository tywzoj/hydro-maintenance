#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/update-trusted-proxies.env"

if [[ -f "$ENV_FILE" ]]; then
	. "$ENV_FILE"
fi

CADDYFILE="${CADDYFILE:-/root/.hydro/Caddyfile}"
REGION="${REGION:-cn-hangzhou}"
SITE_ID="${SITE_ID:-177345139939568}"
DEBUG="${DEBUG:-false}"

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

aliyun esa update-origin-protection-ip-white-list \
	--region "$REGION" \
	--site-id "$SITE_ID" >/dev/null

WHITELIST_JSON="$(aliyun esa update-origin-protection-ip-white-list \
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

echo "Updated trusted proxies in $TARGET_CADDYFILE"
pm2 restart caddy
