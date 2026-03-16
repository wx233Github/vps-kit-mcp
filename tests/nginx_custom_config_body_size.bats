#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.custom.body.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "custom_config 中 client_max_body_size 覆盖默认值" {
  run bash -c '
    set -euo pipefail
    source "$1"
    td="$(mktemp -d /tmp/nginx.custom.body.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT

    export SAFE_PATH_ROOTS=("$td")
    export NGINX_HTTP_CONF_DIR="$td/conf.d"
    export NGINX_WEBROOT_DIR="$td/webroot"
    mkdir -p "$NGINX_HTTP_CONF_DIR" "$NGINX_WEBROOT_DIR"

    cert="$td/test.cer"
    key="$td/test.key"
    : >"$cert"
    : >"$key"

    get_vps_ip() { VPS_IPV6=""; }
    _apply_nginx_conf_with_validation() { cp "$1" "$2"; return 0; }
    _health_check_nginx_config() { return 0; }

    json=$(jq -n --arg p "8080" --arg cert "$cert" --arg key "$key" --arg cc "client_max_body_size 0m;" "{resolved_port:\$p, cert_file:\$cert, key_file:\$key, custom_config:\$cc}")
    _write_and_enable_nginx_config "example.com" "$json"

    conf="$NGINX_HTTP_CONF_DIR/example.com.conf"
    grep -q "client_max_body_size 0m;" "$conf"
    ! grep -q "client_max_body_size 0;" "$conf"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "client_max_body_size 字段优先于 custom_config" {
  run bash -c '
    set -euo pipefail
    source "$1"
    td="$(mktemp -d /tmp/nginx.custom.body.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT

    export SAFE_PATH_ROOTS=("$td")
    export NGINX_HTTP_CONF_DIR="$td/conf.d"
    export NGINX_WEBROOT_DIR="$td/webroot"
    mkdir -p "$NGINX_HTTP_CONF_DIR" "$NGINX_WEBROOT_DIR"

    cert="$td/test.cer"
    key="$td/test.key"
    : >"$cert"
    : >"$key"

    get_vps_ip() { VPS_IPV6=""; }
    _apply_nginx_conf_with_validation() { cp "$1" "$2"; return 0; }
    _health_check_nginx_config() { return 0; }

    cc=$(printf "%s\n" "client_max_body_size 0m;" "proxy_read_timeout 300s;")
    json=$(jq -n --arg p "8080" --arg cert "$cert" --arg key "$key" --arg mb "5m" --arg cc "$cc" "{resolved_port:\$p, cert_file:\$cert, key_file:\$key, client_max_body_size:\$mb, custom_config:\$cc}")
    _write_and_enable_nginx_config "example.com" "$json"

    conf="$NGINX_HTTP_CONF_DIR/example.com.conf"
    grep -q "client_max_body_size 5m;" "$conf"
    ! grep -q "client_max_body_size 0m;" "$conf"
    grep -q "proxy_read_timeout 300s;" "$conf"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}
