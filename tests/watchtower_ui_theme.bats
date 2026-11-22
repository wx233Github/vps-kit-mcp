#!/usr/bin/env bats

setup() {
	export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "watchtower fallback _render_menu 在 retro-launcher 下使用轻量标题样式" {
	run bash -c '
    set -euo pipefail
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/watchtower.theme.menu.XXXXXX.sh)
    sed "s#/opt/vps_install_modules/utils.sh#"$REPO_ROOT/utils.sh"#" "$REPO_ROOT/tools/Watchtower.sh" >"$script_copy"
    source "$script_copy"
    rm -f "$script_copy"
    output=$(_render_menu "Watchtower 自动更新管理器" "1. 测试项" 2>/dev/null)
    [[ "$output" == *"Watchtower 自动更新管理器"* ]]
    [[ "$output" == *"1. 测试项"* ]]
    [[ "$output" != *"--- Watchtower 自动更新管理器 ---"* ]]
  '
	[ "$status" -eq 0 ]
}

@test "watchtower main_menu 在 retro-launcher 下渲染状态与操作分区" {
	run bash -c '
    set -euo pipefail
    JB_UI_THEME="retro-launcher"
    script_copy=$(mktemp /tmp/watchtower.main.theme.XXXXXX.sh)
    sed "s#/opt/vps_install_modules/utils.sh#"$REPO_ROOT/utils.sh"#" "$REPO_ROOT/tools/Watchtower.sh" >"$script_copy"
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
	[[ "$output" == *"Watchtower 自动更新管理器"* ]]
	[[ "$output" == *"当前状态"* ]]
	[[ "$output" == *"下一次扫描"* ]]
	[[ "$output" == *"常用操作"* ]]
	[[ "$output" == *"日志与容器看板"* ]]
}
