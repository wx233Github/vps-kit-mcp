#!/usr/bin/env bats

@test "bbr show_menu 在 retro-launcher 下输出 header 与统一分区" {
	run bash -c '
    set -euo pipefail
    JB_NONINTERACTIVE="true"
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/bbr.theme.menu.XXXXXX.sh)
    sed "\$d" /root/aa/vps-kit-mcp/tools/bbr_ace.sh >"$script_copy"
    source /root/aa/vps-kit-mcp/utils.sh
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
	[[ "$output" == *"Tune congestion control, inspect kernel state and manage network recovery workflows"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Kernel: 6.8.0-test"* ]]
	[[ "$output" == *"Runtime Overview"* ]]
	[[ "$output" == *"Profile Control"* ]]
	[[ "$output" == *"Policy Control"* ]]
	[[ "$output" == *"Recovery & Lifecycle"* ]]
}

@test "bbr kernel_manager 在 retro-launcher 下复用 schema panel header" {
	run bash -c '
    set -euo pipefail
    JB_NONINTERACTIVE="true"
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/bbr.kernel.theme.menu.XXXXXX.sh)
    sed "\$d" /root/aa/vps-kit-mcp/tools/bbr_ace.sh >"$script_copy"
    source /root/aa/vps-kit-mcp/utils.sh
    source "$script_copy"
    rm -f "$script_copy"
    USE_UTILS_UI=1
    kernel_manager
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Kernel lifecycle updates, rollback paths and cleanup operations"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Scope: Kernel"* ]]
	[[ "$output" == *"Use this lane for kernel upgrades, reverting XanMod or pruning old images."* ]]
	[[ "$output" == *"Recovery & Lifecycle"* ]]
}
