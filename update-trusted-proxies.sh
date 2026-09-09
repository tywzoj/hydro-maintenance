#!/bin/bash

CADDYFILE="${CADDYFILE:-/root/.hydro/Caddyfile}"

###################### CONFIGURATION END ######################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_FILE="$SCRIPT_DIR/trusted_proxies.txt"

if [[ ! -r "$PROXY_FILE" ]]; then
	echo "Cannot read trusted proxy list: $PROXY_FILE" >&2
	exit 1
fi

if [[ ! -f "$CADDYFILE" ]]; then
	echo "Caddyfile not found: $CADDYFILE" >&2
	exit 1
fi

TRUSTED_PROXIES=()
while IFS= read -r line || [[ -n "$line" ]]; do
	line="${line%$'\r'}"
	line="${line#"${line%%[![:space:]]*}"}"
	line="${line%"${line##*[![:space:]]}"}"

	if [[ -z "$line" || "$line" == \#* ]]; then
		continue
	fi

	TRUSTED_PROXIES+=("$line")
done < "$PROXY_FILE"

if (( ${#TRUSTED_PROXIES[@]} == 0 )); then
	echo "Trusted proxy list is empty: $PROXY_FILE" >&2
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 is required to validate trusted proxy addresses" >&2
	exit 1
fi

python3 - "${TRUSTED_PROXIES[@]}" <<'PY'
import ipaddress
import re
import sys

for value in sys.argv[1:]:
    if not re.fullmatch(r"[0-9A-Fa-f:.]+", value):
        print(f"Invalid IP address: {value}", file=sys.stderr)
        raise SystemExit(1)
    try:
        ipaddress.ip_address(value)
    except ValueError:
        print(f"Invalid IP address: {value}", file=sys.stderr)
        raise SystemExit(1)
PY

printf -v TRUSTED_PROXY_LIST '%s ' "${TRUSTED_PROXIES[@]}"
TRUSTED_PROXY_LIST="${TRUSTED_PROXY_LIST% }"

TEMP_FILE="$(mktemp "${CADDYFILE}.tmp.XXXXXX")"
trap 'rm -f -- "$TEMP_FILE"' EXIT
cp -p -- "$CADDYFILE" "$TEMP_FILE"

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
' "$CADDYFILE" > "$TEMP_FILE"; then
	echo "No trusted_proxies static directive found in a servers block" >&2
	exit 1
fi

mv -- "$TEMP_FILE" "$CADDYFILE"
trap - EXIT

echo "Updated trusted proxies in $CADDYFILE"
