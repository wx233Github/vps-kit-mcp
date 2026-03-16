#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.http2.fix.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "http2 旧写法升级后批量修正" {
  run bash -c '
    set -euo pipefail
    source "$1"
    td="$(mktemp -d /tmp/nginx.http2.fix.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT

    export SAFE_PATH_ROOTS=("$td")
    export NGINX_HTTP_CONF_DIR="$td/conf.d"
    export LOCK_OWNER_PID_HTTP="$$"
    mkdir -p "$NGINX_HTTP_CONF_DIR"

    conf="$NGINX_HTTP_CONF_DIR/example.conf"
    cat >"$conf" <<"EOF"
server {
    listen 443 ssl http2;
    server_name example.com;
}
EOF

    _get_nginx_version() { printf "%s\n" "1.28.2"; }
    _ensure_nginx_in_path() { return 0; }
    nginx() { if [ "${1:-}" = "-t" ]; then return 0; fi; return 0; }

    _fix_http2_listen_after_upgrade

    grep -q "listen 443 ssl;" "$conf"
    grep -q "http2 on;" "$conf"
    [ -f "$conf.bak" ]
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "http2 修正失败触发回滚" {
  run bash -c '
    set -euo pipefail
    source "$1"
    td="$(mktemp -d /tmp/nginx.http2.fix.fail.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT

    export SAFE_PATH_ROOTS=("$td")
    export NGINX_HTTP_CONF_DIR="$td/conf.d"
    export LOCK_OWNER_PID_HTTP="$$"
    mkdir -p "$NGINX_HTTP_CONF_DIR"

    conf="$NGINX_HTTP_CONF_DIR/example.conf"
    cat >"$conf" <<"EOF"
server {
    listen 443 ssl http2;
    server_name example.com;
}
EOF

    _get_nginx_version() { printf "%s\n" "1.28.2"; }
    _ensure_nginx_in_path() { return 0; }
    nginx() { if [ "${1:-}" = "-t" ]; then return 1; fi; return 0; }

    set +e
    _fix_http2_listen_after_upgrade
    rc=$?
    set -e

    [ "$rc" -ne 0 ]
    grep -q "listen 443 ssl http2;" "$conf"
    [ -f "$conf.bak" ]
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "版本不足时跳过修正" {
  run bash -c '
    set -euo pipefail
    source "$1"
    td="$(mktemp -d /tmp/nginx.http2.fix.skip.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT

    export SAFE_PATH_ROOTS=("$td")
    export NGINX_HTTP_CONF_DIR="$td/conf.d"
    export LOCK_OWNER_PID_HTTP="$$"
    mkdir -p "$NGINX_HTTP_CONF_DIR"

    conf="$NGINX_HTTP_CONF_DIR/example.conf"
    cat >"$conf" <<"EOF"
server {
    listen 443 ssl http2;
    server_name example.com;
}
EOF

    _get_nginx_version() { printf "%s\n" "1.24.0"; }
    _ensure_nginx_in_path() { return 0; }
    nginx() { if [ "${1:-}" = "-t" ]; then return 0; fi; return 0; }

    _fix_http2_listen_after_upgrade

    grep -q "listen 443 ssl http2;" "$conf"
    [ ! -f "$conf.bak" ]
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
}
