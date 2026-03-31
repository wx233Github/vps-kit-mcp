#!/usr/bin/env bats

@test "watchtower fallback _render_menu 在 retro-launcher 下使用轻量标题样式" {
	run bash -c '
    set -euo pipefail
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/watchtower.theme.menu.XXXXXX.sh)
    awk "{gsub(\"/opt/vps_install_modules/utils.sh\", \"/root/aa/vps-kit-mcp/utils.sh\"); print}" /root/aa/vps-kit-mcp/tools/Watchtower.sh >"$script_copy"
    source "$script_copy"
    rm -f "$script_copy"
    output=$(_render_menu "Watchtower 自动更新管理器" "1. 测试项" 2>/dev/null)
    [[ "$output" == *"Watchtower 自动更新管理器"* ]]
    [[ "$output" == *"1. 测试项"* ]]
    [[ "$output" != *"--- Watchtower 自动更新管理器 ---"* ]]
  '
	[ "$status" -eq 0 ]
}

@test "watchtower main_menu 在 retro-launcher 下输出 header 与分区" {
	run bash -c '
    set -euo pipefail
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/watchtower.main.theme.XXXXXX.sh)
    awk "{gsub(\"/opt/vps_install_modules/utils.sh\", \"/root/aa/vps-kit-mcp/utils.sh\"); print}" /root/aa/vps-kit-mcp/tools/Watchtower.sh >"$script_copy"
    source "$script_copy"
    rm -f "$script_copy"
    load_config() { return 0; }
    should_clear_screen() { return 1; }
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "docker" ]; then
        return 0
      fi
      builtin command "$@"
    }
    _watchtower_is_running() { return 0; }
    get_watchtower_inspect_summary() { printf "%s" "21600|interval|ghcr.io/containrrr/watchtower|latest||DockerNode|empty"; }
    get_watchtower_all_raw_logs() { printf "%s" ""; }
    _extract_schedule_from_env() { printf "%s" ""; }
    _get_watchtower_next_run_time() { printf "%s" "4h later"; }
    stat() { printf "%s" "0"; }
    _watchtower_inspect_created() { printf "%s" ""; }
    _prompt_for_menu_choice() { printf "%s" ""; }
    main_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Manage container auto-updates, notifications and runtime recovery workflows"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Service: 已启动"* ]]
	[[ "$output" == *"Service Overview"* ]]
	[[ "$output" == *"Action Center"* ]]
	[[ "$output" == *"实时日志与容器看板"* ]]
}
