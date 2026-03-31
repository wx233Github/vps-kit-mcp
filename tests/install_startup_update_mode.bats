#!/usr/bin/env bats

setup() {
	REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
	SCRIPT_PATH="${REPO_ROOT}/install.sh"
	LIB_PATH="$(mktemp /tmp/install.startup.mode.XXXXXX.sh)"
	awk '
    /if \[ "\$REAL_SCRIPT_PATH" != "\$FINAL_SCRIPT_PATH" \]; then/ {skip=1; next}
    skip && /# --- 主程序依赖加载 ---/ {skip=0; print; next}
    !skip {print}
  ' "$SCRIPT_PATH" | sed '$d' >"$LIB_PATH"
}

teardown() {
	rm -f "$LIB_PATH"
}

@test "startup_update_mode_label 返回中文标签" {
	run bash -c '
    set -euo pipefail
    source "$1"
    [ "$(startup_update_mode_label background)" = "后台" ]
    [ "$(startup_update_mode_label legacy)" = "前台" ]
    [ "$(startup_update_mode_label unknown)" = "未知" ]
  ' _ "$LIB_PATH"
	[ "$status" -eq 0 ]
}

@test "set_startup_update_mode 写入配置" {
	run bash -c '
    set -euo pipefail
    source "$1"
    CONFIG_PATH="$(mktemp /tmp/install.startup.mode.config.XXXXXX.json)"
    printf "%s" "{}" >"$CONFIG_PATH"
    set_startup_update_mode "background"
    jq -e ".startup_update_mode == \"background\"" "$CONFIG_PATH" >/dev/null
  ' _ "$LIB_PATH"
	[ "$status" -eq 0 ]
}

@test "set_ui_theme 写入 ui.theme" {
	run bash -c '
    set -euo pipefail
    source "$1"
    CONFIG_PATH="$(mktemp /tmp/install.ui.theme.config.XXXXXX.json)"
    printf "%s" "{}" >"$CONFIG_PATH"
    set_ui_theme "classic"
    jq -e ".ui.theme == \"classic\"" "$CONFIG_PATH" >/dev/null
  ' _ "$LIB_PATH"
	[ "$status" -eq 0 ]
}

@test "merge_config_json 保留本地启动模式" {
	run bash -c '
    set -euo pipefail
    source "$1"
    remote="$(mktemp /tmp/install.startup.mode.remote.XXXXXX.json)"
    local_cfg="$(mktemp /tmp/install.startup.mode.local.XXXXXX.json)"
    out="$(mktemp /tmp/install.startup.mode.out.XXXXXX.json)"
    printf "%s" "{\"startup_update_mode\":\"background\",\"base_url\":\"remote\"}" >"$remote"
    printf "%s" "{\"startup_update_mode\":\"legacy\",\"custom\":true}" >"$local_cfg"
    merge_config_json "$remote" "$local_cfg" "$out"
    jq -e ".startup_update_mode == \"legacy\"" "$out" >/dev/null
    jq -e ".base_url == \"remote\"" "$out" >/dev/null
    jq -e ".custom == true" "$out" >/dev/null
  ' _ "$LIB_PATH"
	[ "$status" -eq 0 ]
}

@test "merge_config_json 保留本地 ui.theme" {
	run bash -c '
    set -euo pipefail
    source "$1"
    remote="$(mktemp /tmp/install.ui.theme.remote.XXXXXX.json)"
    local_cfg="$(mktemp /tmp/install.ui.theme.local.XXXXXX.json)"
    out="$(mktemp /tmp/install.ui.theme.out.XXXXXX.json)"
    printf "%s" "{\"ui\":{\"theme\":\"retro-launcher\"},\"base_url\":\"remote\"}" >"$remote"
    printf "%s" "{\"ui\":{\"theme\":\"classic\"},\"custom\":true}" >"$local_cfg"
    merge_config_json "$remote" "$local_cfg" "$out"
    jq -e ".ui.theme == \"classic\"" "$out" >/dev/null
    jq -e ".base_url == \"remote\"" "$out" >/dev/null
    jq -e ".custom == true" "$out" >/dev/null
  ' _ "$LIB_PATH"
	[ "$status" -eq 0 ]
}

@test "ui_theme_label 返回英文标签" {
	run bash -c '
    set -euo pipefail
    source "$1"
    [ "$(ui_theme_label retro-launcher)" = "Retro Launcher" ]
    [ "$(ui_theme_label classic)" = "Classic" ]
    [ "$(ui_theme_label compact)" = "Compact" ]
    [ "$(ui_theme_label minimal)" = "Minimal" ]
  ' _ "$LIB_PATH"
	[ "$status" -eq 0 ]
}

@test "config.json 将主题切换项收纳到 THEME_MENU" {
	run bash -c '
    set -euo pipefail
    config_path="$1"
    jq -e ".menus.MAIN_MENU.items | any(.action == \"THEME_MENU\" and .type == \"submenu\")" "$config_path" >/dev/null
    jq -e "([.menus.MAIN_MENU.items[] | select((.action // \"\") | test(\"^set_theme_\"))] | length) == 0" "$config_path" >/dev/null
    jq -e "([.menus.THEME_MENU.items[] | select((.action // \"\") | test(\"^set_theme_\"))] | length) == 4" "$config_path" >/dev/null
  ' _ "${REPO_ROOT}/config.json"
	[ "$status" -eq 0 ]
}

@test "config.json 为二级菜单补齐分组与描述" {
	run bash -c '
    set -euo pipefail
    config_path="$1"
    jq -e ".menus.TOOLS_MENU.items | all(.[]; ((.group // \"\") | length) > 0 and ((.desc // \"\") | length) > 0)" "$config_path" >/dev/null
    jq -e ".menus.MCP_MENU.items | all(.[]; ((.group // \"\") | length) > 0 and ((.desc // \"\") | length) > 0)" "$config_path" >/dev/null
    jq -e ".menus.THEME_MENU.items | all(.[]; .group == \"profiles\")" "$config_path" >/dev/null
  ' _ "${REPO_ROOT}/config.json"
	[ "$status" -eq 0 ]
}

@test "config.json 为二级菜单补齐 UI 文案与 focus 配置" {
	run bash -c '
    set -euo pipefail
    config_path="$1"
    jq -e ".menus.TOOLS_MENU.ui.subtitle == \"Operational add-ons for container updates and network tuning\"" "$config_path" >/dev/null
    jq -e ".menus.TOOLS_MENU.ui.focus.key == \"modules\"" "$config_path" >/dev/null
    jq -e ".menus.MCP_MENU.ui.groups.runtime == \"Runtime\"" "$config_path" >/dev/null
    jq -e ".menus.THEME_MENU.ui.focus.source == \"current_theme\"" "$config_path" >/dev/null
  ' _ "${REPO_ROOT}/config.json"
	[ "$status" -eq 0 ]
}

@test "config.json 为 MAIN_MENU 补齐首页 UI 文案与分组配置" {
	run bash -c '
    set -euo pipefail
    config_path="$1"
    jq -e ".menus.MAIN_MENU.ui.subtitle == \"One-click VPS operations toolkit for Docker, Nginx, TLS and MCP\"" "$config_path" >/dev/null
    jq -e ".menus.MAIN_MENU.ui.repo == \"Repo: https://github.com/wx233Github/vps-kit-mcp\"" "$config_path" >/dev/null
    jq -e ".menus.MAIN_MENU.ui.meta_labels.version == \"Version\"" "$config_path" >/dev/null
    jq -e ".menus.MAIN_MENU.ui.groups.core == \"Core Modules\"" "$config_path" >/dev/null
  ' _ "${REPO_ROOT}/config.json"
	[ "$status" -eq 0 ]
}

@test "config.json 为菜单补齐状态标签与状态标记配置" {
	run bash -c '
    set -euo pipefail
    config_path="$1"
    jq -e ".menus.MAIN_MENU.ui.status_labels[\"docker.sh\"] == \"Docker\"" "$config_path" >/dev/null
    jq -e ".menus.MAIN_MENU.ui.status_labels[\"THEME_MENU\"] == \"当前\"" "$config_path" >/dev/null
    jq -e ".menus.TOOLS_MENU.ui.status_labels[\"tools/Watchtower.sh\"] == \"Watchtower\"" "$config_path" >/dev/null
    jq -e ".menus.THEME_MENU.ui.status_markers.current == \"Current\"" "$config_path" >/dev/null
  ' _ "${REPO_ROOT}/config.json"
	[ "$status" -eq 0 ]
}

@test "config.json 为菜单补齐 registry 覆盖说明注释" {
	run bash -c '
    set -euo pipefail
    config_path="$1"
	    jq -e ".comment_menu_override_ids | contains(\"DOCKER_INSTALL_MENU\")" "$config_path" >/dev/null
	    jq -e ".comment_menu_override_ids | contains(\"BBR_KERNEL_MENU\")" "$config_path" >/dev/null
    jq -e ".menus.MAIN_MENU.comment_ui | contains(\"registry\")" "$config_path" >/dev/null
    jq -e ".menus.TOOLS_MENU.comment_ui | contains(\"默认词表\")" "$config_path" >/dev/null
    jq -e ".menus.MCP_MENU.comment_ui | contains(\"schema/default registry\")" "$config_path" >/dev/null
    jq -e ".menus.THEME_MENU.comment_ui | contains(\"focus\")" "$config_path" >/dev/null
  ' _ "${REPO_ROOT}/config.json"
	[ "$status" -eq 0 ]
}
