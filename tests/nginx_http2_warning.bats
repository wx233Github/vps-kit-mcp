#!/usr/bin/env bats

@test "http2 warn line appears on unsupported version" {
  tmp_script=$(mktemp /tmp/nginx.http2.warn.XXXXXX.sh)
  cat >"$tmp_script" <<"EOF"
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin"

SCRIPT_PATH="/root/aa/vps-kit-mcp/nginx.sh"
LIB_PATH=$(mktemp /tmp/nginx.http2.warn.lib.XXXXXX.sh)
sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"

realpath() { printf '%s\n' "/root/aa/vps-kit-mcp/nginx.sh"; }

source "$LIB_PATH"

NGINX_HTTP2_DIRECTIVE_MIN_VERSION="1.25.1"

warn_line=$(_nginx_http2_warn_line "1.18.0")
printf '%s\n' "$warn_line"
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
  [ "$status" -eq 0 ]
  [[ "$output" =~ http2\ on ]]
}

@test "http2 warn line is empty on supported version" {
  tmp_script=$(mktemp /tmp/nginx.http2.warn.ok.XXXXXX.sh)
  cat >"$tmp_script" <<"EOF"
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin"

SCRIPT_PATH="/root/aa/vps-kit-mcp/nginx.sh"
LIB_PATH=$(mktemp /tmp/nginx.http2.warn.lib.XXXXXX.sh)
sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"

realpath() { printf '%s\n' "/root/aa/vps-kit-mcp/nginx.sh"; }

source "$LIB_PATH"

NGINX_HTTP2_DIRECTIVE_MIN_VERSION="1.25.1"

warn_line=$(_nginx_http2_warn_line "1.25.1")
printf '%s\n' "$warn_line"
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
