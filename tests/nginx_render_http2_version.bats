#!/usr/bin/env bats

# 渲染 http2 写法按 nginx 版本自适应：< 1.25.1 用旧 listen 写法，>= 1.25.1 用独立指令
_render_http2_conf_for_version() {
  local fake_version="${1:-1.24.0}"
  local tmp_script
  tmp_script=$(mktemp /tmp/nginx.render.http2.XXXXXX.sh)
  cat >"$tmp_script" <<EOF
set -euo pipefail
export HOME="\${HOME:-/root}"
export PATH="/usr/local/bin:/usr/bin:/bin"

SCRIPT_PATH="/root/项目/vps-kit-mcp/nginx.sh"
LIB_PATH=$(mktemp /tmp/nginx.render.http2.lib.XXXXXX.sh)
sed '\$d' "\$SCRIPT_PATH" >"\$LIB_PATH"

realpath() { printf '%s\n' "\$SCRIPT_PATH"; }
source "\$LIB_PATH"

NGINX_HTTP2_DIRECTIVE_MIN_VERSION="1.25.1"

work_dir="\$(mktemp -d /tmp/nginx.render.http2.work.XXXXXX)"
NGINX_HTTP_CONF_DIR="\$work_dir"
NGINX_WEBROOT_DIR="\$work_dir"

get_vps_ip() { VPS_IPV6=""; }
_get_nginx_version() { printf '%s' "${fake_version}"; }
_apply_nginx_conf_with_validation() { cp "\$1" "\$work_dir/captured.conf"; return 0; }
_health_check_nginx_config() { return 0; }
_mark_nginx_conf_changed() { return 0; }

json='{"domain":"example.com","type":"local_port","resolved_port":"52222","cert_file":"/tmp/dummy.cer","key_file":"/tmp/dummy.key","client_max_body_size":"","custom_config":"","cf_strict_mode":"n"}'
_write_and_enable_nginx_config "example.com" "\$json" >/dev/null 2>&1
cat "\$work_dir/captured.conf"
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
}

@test "nginx < 1.25.1 渲染旧 listen http2 写法" {
  _render_http2_conf_for_version "1.24.0"
  [ "$status" -eq 0 ]
  [[ "$output" =~ listen\ 443\ ssl\ http2\; ]]
  [[ "$output" != *"    http2 on;"* ]]
}

@test "nginx >= 1.25.1 渲染独立 http2 on 指令" {
  _render_http2_conf_for_version "1.26.0"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "    http2 on;" ]]
  [[ "$output" =~ "listen 443 ssl;" ]]
}

@test "nginx 版本未知时回退旧写法" {
  _render_http2_conf_for_version ""
  [ "$status" -eq 0 ]
  [[ "$output" =~ listen\ 443\ ssl\ http2\; ]]
}
