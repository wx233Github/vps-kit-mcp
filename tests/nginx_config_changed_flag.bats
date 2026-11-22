#!/usr/bin/env bats
# Coverage Matrix
# - _nginx_config_changed: 推进代数、失效 nginx -t 与重载策略缓存、标记待重载
# - _nginx_request_reload: 只标记待重载，不动代数与缓存
# - _nginx_store_test_result: 以当前代数记录 nginx -t 结果
# - _nginx_reload_done: 清除待重载标记
#
# Fixture Conventions
# - sed '$d' nginx.sh > 临时 lib，子 shell 内 source
# - 不触碰真实 nginx / systemctl

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.config.changed.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "配置变更动词推进代数并失效两个缓存，同时标记待重载" {
  run bash -c '
    source "$1"
    NGINX_CONF_GEN=2
    NGINX_TEST_CACHE_GEN=2
    NGINX_TEST_CACHE_TS=100
    NGINX_TEST_CACHE_RESULT=0
    NGINX_RELOAD_STRATEGY_CACHE="systemctl"
    NGINX_RELOAD_STRATEGY_CACHE_TS=100
    NGINX_RELOAD_NEEDED="false"
    _nginx_config_changed
    printf "gen=%s\n" "$NGINX_CONF_GEN"
    printf "test_gen=%s\n" "$NGINX_TEST_CACHE_GEN"
    printf "test_ts=%s\n" "$NGINX_TEST_CACHE_TS"
    printf "strat=[%s]\n" "$NGINX_RELOAD_STRATEGY_CACHE"
    printf "strat_ts=%s\n" "$NGINX_RELOAD_STRATEGY_CACHE_TS"
    printf "reload=%s\n" "$NGINX_RELOAD_NEEDED"
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "gen=3" ]
  [ "${lines[1]}" = "test_gen=-1" ]
  [ "${lines[2]}" = "test_ts=0" ]
  [ "${lines[3]}" = "strat=[]" ]
  [ "${lines[4]}" = "strat_ts=0" ]
  [ "${lines[5]}" = "reload=true" ]
}

@test "旧名 _mark_nginx_conf_changed 等价于配置变更动词" {
  run bash -c '
    source "$1"
    NGINX_CONF_GEN=0
    NGINX_TEST_CACHE_GEN=0
    NGINX_RELOAD_NEEDED="false"
    _mark_nginx_conf_changed
    printf "gen=%s test_gen=%s reload=%s\n" "$NGINX_CONF_GEN" "$NGINX_TEST_CACHE_GEN" "$NGINX_RELOAD_NEEDED"
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "gen=1 test_gen=-1 reload=true" ]
}

@test "仅请求重载不推进代数、不失效测试缓存" {
  run bash -c '
    source "$1"
    NGINX_CONF_GEN=5
    NGINX_TEST_CACHE_GEN=5
    NGINX_TEST_CACHE_TS=200
    NGINX_RELOAD_NEEDED="false"
    _nginx_request_reload
    printf "gen=%s test_gen=%s test_ts=%s reload=%s\n" "$NGINX_CONF_GEN" "$NGINX_TEST_CACHE_GEN" "$NGINX_TEST_CACHE_TS" "$NGINX_RELOAD_NEEDED"
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "gen=5 test_gen=5 test_ts=200 reload=true" ]
}

@test "记录 nginx -t 结果时绑定当前代数与当前时间戳" {
  run bash -c '
    source "$1"
    NGINX_CONF_GEN=7
    NGINX_TEST_CACHE_GEN=-1
    NGINX_TEST_CACHE_TS=0
    NGINX_TEST_CACHE_RESULT=9
    date() { printf "%s\n" "12345"; }
    _nginx_store_test_result 1
    printf "result=%s gen=%s ts=%s\n" "$NGINX_TEST_CACHE_RESULT" "$NGINX_TEST_CACHE_GEN" "$NGINX_TEST_CACHE_TS"
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "result=1 gen=7 ts=12345" ]
}

@test "重载成功动词清除待重载标记" {
  run bash -c '
    source "$1"
    NGINX_RELOAD_NEEDED="true"
    _nginx_reload_done
    printf "%s\n" "$NGINX_RELOAD_NEEDED"
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
