#!/usr/bin/env bats
# Coverage Matrix
# - _draw_dashboard: 标题只出现一次，版本号右对齐到分隔线宽度
# - _nginx_alert_count: 告警数 = 状态区非正常项数量
# - _nginx_uptime_cn: 周 / 天 / 小时 / 分钟 四种粒度
#
# Fixture Conventions
# - 依赖全部 stub，不访问真实 nginx、证书或上游；项目元数据用临时 JSON。

setup() {
  SCRIPT_PATH="${BATS_TEST_DIRNAME%/tests}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.dash.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
  WORK_DIR="$(mktemp -d /tmp/nginx.dash.dir.XXXXXX)"
  printf '%s' '[{"domain":"a","cert_file":"/c/a"},{"domain":"b","cert_file":"/c/b"}]' >"$WORK_DIR/p.json"
  printf '%s' '[]' >"$WORK_DIR/t.json"
}

teardown() {
  rm -f "$LIB_PATH"
  rm -rf "$WORK_DIR"
}

@test "_draw_dashboard: 标题只出现一次且版本号紧跟标题" {
  run bash -c '
    source "$1"
    PROJECTS_METADATA_FILE="$2/p.json"
    TCP_PROJECTS_METADATA_FILE="$2/t.json"
    _generate_op_id() { :; }
    _ensure_nginx_in_path() { return 0; }
    _get_nginx_version() { printf "%s" 1.26.3; }
    _nginx_config_health_status() { printf "正常\t\n"; }
    _nginx_cert_health_status() { printf "异常\tx 证书已过期\n"; }
    _nginx_upstream_meta() { printf "%s\t%s" 1.30.6 "1.30 1.28 1.26"; }
    _nginx_multi_instance_line() { :; }
    _nginx_http2_warn_line() { :; }
    generate_line() { local w="$1" c="$2" i=0 o=""; while [ "$i" -lt "$w" ]; do o+="$c"; i=$((i+1)); done; printf "%s" "$o"; }
    COLUMNS=45 _draw_dashboard
  ' _ "$LIB_PATH" "$WORK_DIR"
  [ "$status" -eq 0 ]
  local plain
  plain=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g')
  [ "$(printf '%s\n' "$plain" | grep -c '^Nginx')" -eq 1 ]
  local head_line
  head_line=$(printf '%s\n' "$plain" | grep '^Nginx')
  [ "$head_line" = "Nginx   1.26.3" ]
}

@test "_draw_dashboard: 第二行给出中文运行时长与告警数" {
  run bash -c '
    source "$1"
    PROJECTS_METADATA_FILE="$2/p.json"
    TCP_PROJECTS_METADATA_FILE="$2/t.json"
    _generate_op_id() { :; }
    _ensure_nginx_in_path() { return 0; }
    _get_nginx_version() { printf "%s" 1.26.3; }
    _nginx_config_health_status() { printf "正常\t\n"; }
    _nginx_cert_health_status() { printf "异常\tx 证书已过期\n"; }
    _nginx_uptime_cn() { printf "%s" "15 周 6 天"; }
    _nginx_upstream_meta() { :; }
    _nginx_multi_instance_line() { :; }
    _nginx_http2_warn_line() { :; }
    generate_line() { local w="$1" c="$2" i=0 o=""; while [ "$i" -lt "$w" ]; do o+="$c"; i=$((i+1)); done; printf "%s" "$o"; }
    COLUMNS=45 _draw_dashboard
  ' _ "$LIB_PATH" "$WORK_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"已运行 15 周 6 天"* ]]
  [[ "$output" == *"HTTP 2"* ]]
  [[ "$output" == *"TCP 0"* ]]
  [[ "$output" == *"证书 2"* ]]
  [[ "$output" == *"告警 1"* ]]
  # 旧的英文运行时长不应再出现
  [[ "$output" != *"weeks"* ]]
}

@test "_nginx_alert_count: 只统计非正常项" {
  run bash -c '
    source "$1"
    _nginx_config_health_status() { printf "正常\t\n"; }
    _nginx_cert_health_status() { printf "正常\t\n"; }
    _nginx_alert_count
    printf "\n"
    _NGINX_HEALTH_CACHED=0
    _nginx_config_health_status() { printf "需关注\tx\n"; }
    _nginx_cert_health_status() { printf "异常\ty\n"; }
    _nginx_alert_count
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "0" ]
  [ "${lines[1]}" = "2" ]
}

@test "_nginx_uptime_cn: 按 分/时/天/周/月/年 阶梯自动进阶，最多两档" {
  run bash -c '
    source "$1"
    _nginx_uptime_cn 63072000
    printf "\n"
    _nginx_uptime_cn 39312000
    printf "\n"
    _nginx_uptime_cn 12960000
    printf "\n"
    _nginx_uptime_cn 1209600
    printf "\n"
    _nginx_uptime_cn 1123200
    printf "\n"
    _nginx_uptime_cn 90000
    printf "\n"
    _nginx_uptime_cn 7200
    printf "\n"
    _nginx_uptime_cn 120
    printf "\n"
    _nginx_uptime_cn 0
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2 年" ]
  [ "${lines[1]}" = "1 年 3 月" ]
  [ "${lines[2]}" = "5 月" ]
  [ "${lines[3]}" = "2 周" ]
  [ "${lines[4]}" = "1 周 6 天" ]
  [ "${lines[5]}" = "1 天 1 时" ]
  [ "${lines[6]}" = "2 时" ]
  [ "${lines[7]}" = "2 分" ]
  [ "${lines[8]}" = "0 分" ]
}

@test "_nginx_new_version_line: 两行结构（问题 + 菜单入口）" {
  run bash -c '
    source "$1"
    _nginx_upstream_meta() { printf "%s\t%s" 1.30.6 "1.30 1.28 1.26"; }
    _nginx_new_version_line 1.26.3
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "当前 1.26 分支已停止维护（1.26.3），建议升级到稳定版 1.30.6" ]
  [[ "${lines[1]}" == *"→ 菜单 12" ]]
}

@test "_draw_dashboard: 版本号紧跟标题，不随终端变宽拉远" {
  run bash -c '
    source "$1"
    PROJECTS_METADATA_FILE="$2/p.json"
    TCP_PROJECTS_METADATA_FILE="$2/t.json"
    _generate_op_id() { :; }
    _ensure_nginx_in_path() { return 0; }
    _get_nginx_version() { printf "%s" 1.26.3; }
    _nginx_config_health_status() { printf "正常\t\n"; }
    _nginx_cert_health_status() { printf "正常\t\n"; }
    _nginx_upstream_meta() { :; }
    _nginx_multi_instance_line() { :; }
    _nginx_http2_warn_line() { :; }
    generate_line() { local w="$1" c="$2" i=0 o=""; while [ "$i" -lt "$w" ]; do o+="$c"; i=$((i+1)); done; printf "%s" "$o"; }
    COLUMNS=100 _draw_dashboard
  ' _ "$LIB_PATH" "$WORK_DIR"
  [ "$status" -eq 0 ]
  local plain head_line
  plain=$(printf '%s\n' "$output" | sed 's/\x1b\[[0-9;]*m//g')
  head_line=$(printf '%s\n' "$plain" | grep '^Nginx')
  [ "$head_line" = "Nginx   1.26.3" ]
}

@test "_nginx_health_snapshot: 同一屏只执行一次健康检查" {
  run bash -c '
    source "$1"
    CALLS="$2/cfg.calls"
    _nginx_config_health_status() { printf x >>"$CALLS"; printf "正常\t\n"; }
    _nginx_cert_health_status() { printf "异常\ty\n"; }
    _nginx_alert_count >/dev/null
    _nginx_alert_count >/dev/null
    wc -c <"$CALLS" | tr -d " "
  ' _ "$LIB_PATH" "$WORK_DIR"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1" ]
}

@test "_draw_dashboard: 每次重绘都重新体检（缓存不跨屏）" {
  run bash -c '
    source "$1"
    PROJECTS_METADATA_FILE="$2/p.json"
    TCP_PROJECTS_METADATA_FILE="$2/t.json"
    CALLS="$2/health.calls"
    _generate_op_id() { :; }
    _ensure_nginx_in_path() { return 0; }
    _get_nginx_version() { printf "%s" 1.26.3; }
    _nginx_config_health_status() { printf x >>"$CALLS"; printf "正常\t\n"; }
    _nginx_cert_health_status() { printf "正常\t\n"; }
    _nginx_upstream_meta() { :; }
    _nginx_multi_instance_line() { :; }
    _nginx_http2_warn_line() { :; }
    generate_line() { local w="$1" c="$2" i=0 o=""; while [ "$i" -lt "$w" ]; do o+="$c"; i=$((i+1)); done; printf "%s" "$o"; }
    COLUMNS=45 _draw_dashboard >/dev/null
    COLUMNS=45 _draw_dashboard >/dev/null
    wc -c <"$CALLS" | tr -d " "
  ' _ "$LIB_PATH" "$WORK_DIR"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2" ]
}
