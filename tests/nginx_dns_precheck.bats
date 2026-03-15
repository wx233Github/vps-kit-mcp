#!/usr/bin/env bats

@test "dns precheck warns and continues when no A record" {
  tmp_script=$(mktemp /tmp/nginx.dns.precheck.empty.XXXXXX.sh)
  cat >"$tmp_script" <<"EOF"
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin"

SCRIPT_PATH="/root/aa/vps-kit-mcp/nginx.sh"
LIB_PATH=$(mktemp /tmp/nginx.dns.precheck.lib.XXXXXX.sh)
sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"

realpath() { printf '%s\n' "/root/aa/vps-kit-mcp/nginx.sh"; }

source "$LIB_PATH"

log_message() { printf '%s\n' "$2"; }
get_vps_ip() { VPS_IP="1.2.3.4"; }
dig() { return 0; }

_check_dns_resolution "example.com"
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
  [ "$status" -eq 0 ]
  [[ "$output" =~ DNS\ 解析失败 ]]
  [[ "$output" =~ 本机\ IP ]]
  [[ "$output" =~ 解析\ IP\ :\ 无 ]]
}

@test "dns precheck warns and continues on mismatched A record" {
  tmp_script=$(mktemp /tmp/nginx.dns.precheck.mismatch.XXXXXX.sh)
  cat >"$tmp_script" <<"EOF"
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin"

SCRIPT_PATH="/root/aa/vps-kit-mcp/nginx.sh"
LIB_PATH=$(mktemp /tmp/nginx.dns.precheck.lib.XXXXXX.sh)
sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"

realpath() { printf '%s\n' "/root/aa/vps-kit-mcp/nginx.sh"; }

source "$LIB_PATH"

log_message() { printf '%s\n' "$2"; }
get_vps_ip() { VPS_IP="1.2.3.4"; }
dig() { printf '%s\n' "5.6.7.8"; return 0; }

_check_dns_resolution "example.com"
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
  [ "$status" -eq 0 ]
  [[ "$output" =~ DNS\ 解析异常 ]]
  [[ "$output" =~ 本机\ IP ]]
  [[ "$output" =~ 解析\ IP ]]
}
