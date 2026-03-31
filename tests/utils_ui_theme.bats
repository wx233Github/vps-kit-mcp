#!/usr/bin/env bats

setup() {
	REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
	UTILS_PATH="${REPO_ROOT}/utils.sh"
}

@test "load_config 默认读取 retro-launcher 主题" {
	run bash -c '
    set -euo pipefail
    source "$1"
    CONFIG_PATH="$(mktemp /tmp/utils.theme.default.XXXXXX.json)"
    printf "%s" "{}" >"$CONFIG_PATH"
    load_config "$CONFIG_PATH"
    [ "$(get_ui_theme)" = "retro-launcher" ]
  ' _ "$UTILS_PATH"
	[ "$status" -eq 0 ]
}

@test "load_config 读取 classic 主题" {
	run bash -c '
    set -euo pipefail
    source "$1"
    CONFIG_PATH="$(mktemp /tmp/utils.theme.classic.XXXXXX.json)"
    printf "%s" "{\"ui\":{\"theme\":\"classic\"}}" >"$CONFIG_PATH"
    load_config "$CONFIG_PATH"
    [ "$(get_ui_theme)" = "classic" ]
  ' _ "$UTILS_PATH"
	[ "$status" -eq 0 ]
}

@test "JB_UI_THEME 覆盖配置主题" {
	run bash -c '
    set -euo pipefail
    source "$1"
    CONFIG_PATH="$(mktemp /tmp/utils.theme.override.XXXXXX.json)"
    printf "%s" "{\"ui\":{\"theme\":\"classic\"}}" >"$CONFIG_PATH"
    JB_UI_THEME="minimal"
    load_config "$CONFIG_PATH"
    [ "$(get_ui_theme)" = "minimal" ]
  ' _ "$UTILS_PATH"
	[ "$status" -eq 0 ]
}

@test "主菜单 footer 使用 exit 文案" {
	run bash -c '
    set -euo pipefail
    source "$1"
    [ "$(ui_menu_footer_text main)" = "Type an option and press Enter. Press Enter on empty input to exit." ]
  ' _ "$UTILS_PATH"
	[ "$status" -eq 0 ]
}

@test "子菜单 footer 使用 go back 文案" {
	run bash -c '
    set -euo pipefail
    source "$1"
    [ "$(ui_menu_footer_text submenu)" = "Enter a choice. Empty input goes back." ]
  ' _ "$UTILS_PATH"
	[ "$status" -eq 0 ]
}
