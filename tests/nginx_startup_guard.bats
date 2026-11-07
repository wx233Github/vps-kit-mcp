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

@test "_wait_apt_lock: 锁被占用时等待后报错，锁空闲时立即通过" {
  run bash -c '
    source "$1"
    sleep() { :; }
    log_message() { :; }
    fuser() { printf " 12345"; }
    if _wait_apt_lock 3; then printf "busy:pass\n"; else printf "busy:fail\n"; fi
    fuser() { :; }
    if _wait_apt_lock 3; then printf "free:pass\n"; else printf "free:fail\n"; fi
  ' _ "$CORE_PATH"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "busy:fail" ]
  [ "${lines[1]}" = "free:pass" ]
}

@test "_run_in_group_with_timeout: 超时会带走整个进程组" {
  run bash -c '
    source "$1"
    start=$(date +%s)
    _run_in_group_with_timeout 2 sleep 30
    rc=$?
    end=$(date +%s)
    printf "%s %s" "$rc" "$((end - start))"
  ' _ "$CORE_PATH"
  [ "$status" -eq 0 ]
  local rc elapsed
  rc="${output% *}"
  elapsed="${output#* }"
  [ "$rc" -eq 124 ]
  [ "$elapsed" -le 8 ]
}

@test "首装阶段号连续且分母一致（1..5）" {
  local nums denoms
  nums=$(grep -o '_stage [0-9] [0-9]' nginx.sh | awk '{print $2}' | sort -n | tr '\n' ' ')
  denoms=$(grep -o '_stage [0-9] [0-9]' nginx.sh | awk '{print $3}' | sort -u | tr '\n' ' ')
  [ "$nums" = "1 2 3 4 5 " ]
  [ "$denoms" = "5 " ]
}

@test "缺失依赖只由 install_dependencies 报一次 WARN" {
  # check_dependencies 是探测函数，不应自己发 WARN（否则同一件事报两遍）
  ! grep -q 'log_message WARN "缺失依赖' nginx.sh
  grep -q 'log_message WARN "缺少依赖：' nginx.sh
}
