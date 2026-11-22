#!/usr/bin/env bats
# Coverage Matrix
# - _tx_write_nginx_config / _tx_remove_nginx_config：事务侧具名适配层，显式传 rollback_owner=transaction
# - 代码中不再依赖 RENDER_ROLLBACK_OWNER 动态作用域变量
#
# Fixture Conventions
# - sed '$d' nginx.sh > 临时 lib，子 shell 内 source
# - 用 stub 替换底层写入函数，只验证参数透传

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.tx.adapter.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "事务写入适配层显式传入 rollback_owner=transaction" {
  run bash -c '
    source "$1"
    _write_and_enable_nginx_config() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}"; }
    _tx_write_nginx_config "example.com" "{\"a\":1}"
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = 'example.com|{"a":1}|transaction' ]
}

@test "事务删除适配层透传 domain" {
  run bash -c '
    source "$1"
    _remove_and_disable_nginx_config() { printf "%s\n" "$1"; }
    _tx_remove_nginx_config "example.com"
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "example.com" ]
}

@test "库代码不再引用 RENDER_ROLLBACK_OWNER 动态作用域变量" {
  run grep -rn "RENDER_ROLLBACK_OWNER" "${REPO_ROOT}/lib"
  [ "$status" -ne 0 ]
}
