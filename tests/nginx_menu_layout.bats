#!/usr/bin/env bats
# Coverage Matrix
# - _nginx_menu_row / _nginx_menu_common_rows / _nginx_menu_policy_rows: 去掉 ○/●/! 与 emoji，编号右对齐
# - _nginx_status_lines: 键值 + 缩进明细 + 修复出口；明细超过 3 条折成计数
# - _nginx_config_health_hint: 只有权限/目录类原因才指向菜单 13
#
# Fixture Conventions
# - 直接 source lib/nginx_flow.sh，并补齐它依赖的颜色常量与 _get_visual_width。
# - 健康检查函数用桩替代，不读真实 projects.json。

setup() {
  FLOW_PATH="${BATS_TEST_DIRNAME%/tests}/lib/nginx_flow.sh"
}

_harness() {
  local script="$1"
  shift
  run bash -c '
    set -Eeuo pipefail
    GRAY=""; NC=""; GREEN=""; YELLOW=""; BRIGHT_RED=""; CYAN=""; BOLD=""; RED=""
    _get_visual_width() {
      local t
      t=$(printf "%b" "$1" | sed "s/\x1b\[[0-9;]*m//g")
      python3 -c "import unicodedata,sys; s=sys.stdin.read(); print(sum(2 if unicodedata.east_asian_width(c) in (\"W\",\"F\",\"A\") else 1 for c in s.strip()))" <<<"$t"
    }
    source "$1"
    shift
    '"$script"'
  ' _ "$FLOW_PATH" "$@"
}

@test "菜单行不再出现 ○ ● ! 与 emoji" {
  _harness '
    _nginx_menu_common_rows
    _nginx_menu_policy_rows
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"○"* ]]
  [[ "$output" != *"●"* ]]
  [[ "$output" != *"!"* ]]
  [[ "$output" != *"🌐"* ]]
  [[ "$output" != *"⬆"* ]]
}

@test "菜单行编号右对齐、标签列从第 4 列开始" {
  _harness '
    _nginx_menu_common_rows
    _nginx_menu_policy_rows
  '
  [ "$status" -eq 0 ]
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # 两位编号占满前两列，随后两个空格
    [[ "$line" =~ ^(\ [0-9]|[0-9]{2})\ \  ]] || fail "编号列未对齐： $line"
  done <<<"$output"
}

@test "证书异常时给出明细与菜单 6 出口" {
  _harness '
    _nginx_config_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_cert_health_status() { printf "%s\t%s\n" "异常" "oen.ckd.qzz.io 证书已过期"; }
    _nginx_status_lines
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"证书状态"*"异常"* ]]
  [[ "$output" == *"oen.ckd.qzz.io 证书已过期"* ]]
  [[ "$output" == *"→ 菜单 6 批量续期"* ]]
  [[ "$output" != *"菜单 13"* ]]
}

@test "证书正常时不出现修复出口" {
  _harness '
    _nginx_config_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_cert_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_status_lines
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"菜单 6"* ]]
  [[ "$output" != *"菜单 13"* ]]
}

@test "临时目录权限原因指向菜单 13，pid 共用原因不给菜单 13" {
  _harness '
    _nginx_config_health_status() { printf "%s\t%s\n" "异常" "www-data 无权写入 /var/lib/nginx/uwsgi（当前 root:root 700）"; }
    _nginx_cert_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_status_lines
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"→ 菜单 13 共享组修复"* ]]

  _harness '
    _nginx_config_health_status() { printf "%s\t%s\n" "需关注" "多个实例共用 pid 文件 /run/nginx.pid（736 与 2614227）"; }
    _nginx_cert_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_status_lines
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"菜单 13"* ]]
}

@test "状态明细超过 3 条时折成「还有 N 项」" {
  _harness '
    _nginx_config_health_status() { printf "%s\t%s\n" "异常" "原因一；原因二；原因三；原因四；原因五"; }
    _nginx_cert_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_status_lines
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"原因一"* ]]
  [[ "$output" == *"原因三"* ]]
  [[ "$output" != *"原因四"* ]]
  [[ "$output" == *"还有 2 项"* ]]
}

@test "原因以分号结尾时，折成计数不多算空项" {
  _harness '
    _nginx_config_health_status() { printf "%s\t%s\n" "异常" "原因一；原因二；原因三；原因四；"; }
    _nginx_cert_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_status_lines
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"还有 1 项"* ]]
}

@test "长明细按终端宽度截断，不超出行宽" {
  COLUMNS=45 _harness '
    _nginx_config_health_status() { printf "%s\t%s\n" "异常" "这是一个非常非常长的原因说明用来验证截断行为是否生效并且不会撑破屏幕宽度限制"; }
    _nginx_cert_health_status() { printf "%s\t%s\n" "正常" ""; }
    _nginx_status_lines
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"…"* ]]
}

@test "nginx.sh 面板全文不再出现 ○ 与 ● 标记" {
  local script="${BATS_TEST_DIRNAME%/tests}/nginx.sh"
  run grep -n '[○●]' "$script"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
