#!/usr/bin/env bats
# Coverage Matrix
# - _filter_systemd_noise: 过滤 journalctl/status 的占位行，保留真实失败原因
# - _collect_systemd_nginx_fail_reason: 无有效日志时退回服务状态，不输出 "-- No entries --"
# - _ensure_systemd_nginx_running_or_warn: systemctl 调用带超时（防 SSH 会话被一起挂死）
#
# Fixture Conventions
# - 直接 source lib/nginx_core.sh，用桩替换 journalctl/systemctl，不触碰真实服务。

setup() {
  CORE_PATH="${BATS_TEST_DIRNAME%/tests}/lib/nginx_core.sh"
}

@test "_filter_systemd_noise: 丢弃占位行保留真实原因" {
  run bash -c '
    source "$1"
    a=$(printf -- "-- No entries --\n" | _filter_systemd_noise)
    b=$(printf -- "-- Logs begin at Fri 2026-11-06 10:00:00 CST --\n-- No entries --\n" | _filter_systemd_noise)
    c=$(printf -- "nginx: [emerg] bind() to 0.0.0.0:80 failed\n" | _filter_systemd_noise)
    printf "[%s][%s][%s]" "$a" "$b" "$c"
  ' _ "$CORE_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "[][][nginx: [emerg] bind() to 0.0.0.0:80 failed]" ]
}

@test "_collect_systemd_nginx_fail_reason: 只有占位行时退回服务状态" {
  run bash -c '
    source "$1"
    journalctl() { printf -- "-- No entries --\n"; }
    systemctl() {
      case "$1" in
      status) printf -- "-- No entries --\n-- Logs begin at x --\n" ;;
      is-active) printf "inactive\n" ;;
      *) return 0 ;;
      esac
    }
    _collect_systemd_nginx_fail_reason
  ' _ "$CORE_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == 服务状态:* ]]
  [[ "$output" != *"No entries"* ]]
}

@test "_ensure_systemd_nginx_running_or_warn: systemctl 调用统一带超时" {
  run bash -c '
    source "$1"
    CALLS="$2/calls.log"
    : >"$CALLS"
    _systemctl_timeout() {
      printf "%s|" "$@" >>"$CALLS"
      case "$2" in
      is-active) return 1 ;;
      *) return 0 ;;
      esac
    }
    _collect_port_occupiers() { return 0; }
    log_message() { :; }
    _ensure_systemd_nginx_running_or_warn
    cat "$CALLS"
  ' _ "$CORE_PATH" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"10|is-active|--quiet|nginx|"* ]]
  [[ "$output" == *"30|enable|--now|nginx|"* ]]
}
