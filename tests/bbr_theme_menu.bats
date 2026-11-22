#!/usr/bin/env bats

setup() {
	export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "bbr show_menu 在 retro-launcher 下输出 header 与统一分区" {
	run bash -c '
    set -euo pipefail
    JB_NONINTERACTIVE="true"
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/bbr.theme.menu.XXXXXX.sh)
    sed -e "\$d" -e "s#/opt/vps_install_modules#/tmp/bbr_test_base#g" "$REPO_ROOT/tools/bbr_ace.sh" >"$script_copy"
    source "$REPO_ROOT/utils.sh"
    source "$script_copy"
    rm -f "$script_copy"
    USE_UTILS_UI=1
    TOTAL_MEM_KB=2097152
    read_current_mode() { printf "%s" "stock"; }
    sysctl() {
      case "$*" in
        "-n net.ipv4.tcp_congestion_control") printf "%s" "bbr" ;;
        "-n net.core.default_qdisc") printf "%s" "fq" ;;
        *) return 1 ;;
      esac
    }
    ss() { printf "%s\n%s\n" "State Recv-Q Send-Q Local Address:Port Peer Address:Port" "ESTAB 0 0 127.0.0.1:ssh 127.0.0.1:12345"; }
    uname() { printf "%s" "6.8.0-test"; }
    show_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"BBR ACE"* ]]
	[[ "$output" == *"当前状态"* ]]
	[[ "$output" == *"常用操作"* ]]
	[[ "$output" == *"网络策略"* ]]
	[[ "$output" == *"维护与恢复"* ]]
	[[ "$output" == *"BBR+FQ 标准模式"* ]]
}

@test "bbr kernel_manager 在 retro-launcher 下复用 schema panel header" {
	run bash -c '
    set -euo pipefail
    JB_NONINTERACTIVE="true"
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/bbr.kernel.theme.menu.XXXXXX.sh)
    sed -e "\$d" -e "s#/opt/vps_install_modules#/tmp/bbr_test_base#g" "$REPO_ROOT/tools/bbr_ace.sh" >"$script_copy"
    source "$REPO_ROOT/utils.sh"
    source "$script_copy"
    rm -f "$script_copy"
    USE_UTILS_UI=1
    kernel_manager
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"BBR ACE - 内核维护"* ]]
	[[ "$output" == *"主题: 启动器风格   |   焦点: 范围: 内核"* ]]
	[[ "$output" == *"请选择内核升级、回退或清理操作。"* ]]
	[[ "$output" == *"维护与恢复"* ]]
}
