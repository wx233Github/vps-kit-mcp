#!/usr/bin/env bats

setup() {
	export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "ui_meta_focus_line 使用受控 focus 标签输出" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="retro-launcher"
    [ "$(ui_meta_focus_line runtime Ready)" = "主题: 启动器风格   |   焦点: 运行状态: Ready" ]
    [ "$(ui_meta_focus_line service Running)" = "主题: 启动器风格   |   焦点: 服务: Running" ]
    [ "$(ui_meta_focus_line plane "Edge Gateway")" = "主题: 启动器风格   |   焦点: 入口: Edge Gateway" ]
    [ "$(ui_meta_focus_line modules 2)" = "主题: 启动器风格   |   焦点: 模块: 2" ]
  '
	[ "$status" -eq 0 ]
}

@test "ui_render_plain_menu 输出稳定的标题分隔结构" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="retro-launcher"
    output=$(ui_render_plain_menu /dev/stdout "Sample Menu" "Line A" "$(ui_meta_focus_line runtime Ready)" "Line B")
    [[ "$output" == *"Sample Menu"* ]]
    [[ "$output" == *"主题: 启动器风格   |   焦点: 运行状态: Ready"* ]]
    [[ "$output" == *"────────────────────────────────────────────────────────────"* ]]
  '
	[ "$status" -eq 0 ]
}

@test "ui_append_panel_header 按统一顺序追加 header 三行" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="retro-launcher"
    lines=()
    ui_append_panel_header lines "Panel subtitle" runtime Ready "Panel hint"
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "Panel subtitle" ]
    [ "${lines[1]}" = "主题: 启动器风格   |   焦点: 运行状态: Ready" ]
    [ "${lines[2]}" = "Panel hint" ]
  '
	[ "$status" -eq 0 ]
}

@test "ui_append_context_lines 只追加非空行" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    lines=()
    ui_append_context_lines lines "Line A" "" "Line B"
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "Line A" ]
    [ "${lines[1]}" = "Line B" ]
  '
	[ "$status" -eq 0 ]
}

@test "ui_append_main_menu_context 按顺序拼接首页上下文" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    lines=()
    ui_append_main_menu_context lines "Toolkit subtitle" "主题: 紧凑风格   |   焦点: 模块: 2" "Repo: example/repo"
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = "Toolkit subtitle" ]
    [ "${lines[1]}" = "主题: 紧凑风格   |   焦点: 模块: 2" ]
    [ "${lines[2]}" = "Repo: example/repo" ]
  '
	[ "$status" -eq 0 ]
}

@test "ui_append_page_block 追加空行标题与内容块" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="retro-launcher"
    lines=("Header line")
    ui_append_page_block lines "Section Title" "Item A" "Item B"
    [ "${#lines[@]}" -eq 6 ]
    [ "${lines[0]}" = "Header line" ]
    [ -z "${lines[1]}" ]
    [[ "${lines[2]}" == *"Section Title"* ]]
    [ -z "${lines[3]}" ]
    [ "${lines[4]}" = "Item A" ]
    [ "${lines[5]}" = "Item B" ]
  '
	[ "$status" -eq 0 ]
}

@test "schema fallback helper 在无显式 schema wrapper 时也能拼装 header 与 block" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="retro-launcher"
    lines=()
    ui_append_schema_or_fallback_panel_header lines "CUSTOM_MENU" "Ready" "runtime" "Fallback subtitle" "Fallback hint"
    ui_append_schema_or_fallback_page_block lines "CUSTOM_MENU" "runtime_overview" "Fallback Section" "Item A"
    [ "${lines[0]}" = "Fallback subtitle" ]
    [ "${lines[1]}" = "主题: 启动器风格   |   焦点: 运行状态: Ready" ]
    [ "${lines[2]}" = "Fallback hint" ]
    [ -z "${lines[3]}" ]
    [[ "${lines[4]}" == *"Fallback Section"* ]]
    [ -z "${lines[5]}" ]
    [ "${lines[6]}" = "Item A" ]
  '
	[ "$status" -eq 0 ]
}

@test "manual fallback helper 统一拼装 header 与 block" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    lines=()
    ui_append_manual_panel_fallback lines "Manual subtitle" "Manual meta" "Manual hint"
    ui_append_manual_page_block lines "Manual heading" "Item A" "Item B"
    [ "${lines[0]}" = "Manual subtitle" ]
    [ "${lines[1]}" = "Manual meta" ]
    [ "${lines[2]}" = "Manual hint" ]
    [ -z "${lines[3]}" ]
    [ "${lines[4]}" = "Manual heading" ]
    [ -z "${lines[5]}" ]
    [ "${lines[6]}" = "Item A" ]
    [ "${lines[7]}" = "Item B" ]
  '
	[ "$status" -eq 0 ]
}

@test "ui_define_manual_fallback_helpers 可重新注册 manual fallback helper" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    unset -f ui_append_manual_panel_fallback
    unset -f ui_append_manual_page_block
    ui_define_manual_fallback_helpers
    lines=()
    ui_append_manual_panel_fallback lines "Manual subtitle" "Manual meta" "Manual hint"
    ui_append_manual_page_block lines "Manual heading" "Item A"
    [ "${lines[0]}" = "Manual subtitle" ]
    [ "${lines[1]}" = "Manual meta" ]
    [ "${lines[2]}" = "Manual hint" ]
    [ -z "${lines[3]}" ]
    [ "${lines[4]}" = "Manual heading" ]
    [ -z "${lines[5]}" ]
    [ "${lines[6]}" = "Item A" ]
  '
	[ "$status" -eq 0 ]
}

@test "ui_define_meta_fallback_helpers 可统一回退 Theme 与 Focus 行" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    unset -f ui_meta_focus_fallback_line
    ui_define_meta_fallback_helpers
    JB_UI_THEME="retro-launcher"
    [ "$(ui_meta_focus_fallback_line runtime Ready)" = "主题: 启动器风格   |   焦点: 运行状态: Ready" ]
	    focus_line=$(ui_meta_focus_fallback_line plane "Edge Gateway")
	    [ "$focus_line" = "主题: 启动器风格   |   焦点: 入口: Edge Gateway" ]
  '
	[ "$status" -eq 0 ]
}

@test "nginx flow 可在缺少共享 manual helper 时回退到本地兼容实现" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    unset -f ui_append_manual_panel_fallback
    unset -f ui_append_manual_page_block
    source "$REPO_ROOT/lib/nginx_flow.sh"
    lines=()
    ui_append_manual_panel_fallback lines "Nginx subtitle" "Nginx meta" "Nginx hint"
    ui_append_manual_page_block lines "Traffic Block" "Item A"
    [ "${lines[0]}" = "Nginx subtitle" ]
    [ "${lines[1]}" = "Nginx meta" ]
    [ "${lines[2]}" = "Nginx hint" ]
    [ -z "${lines[3]}" ]
    [ "${lines[4]}" = "Traffic Block" ]
    [ -z "${lines[5]}" ]
    [ "${lines[6]}" = "Item A" ]
  '
	[ "$status" -eq 0 ]
}

@test "ui_render_main_menu_hero 在 compact 下复用 context 组装" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="compact"
    output=$(ui_render_main_menu_hero "VPS-Kit MCP" "Toolkit subtitle" "主题: 紧凑风格   |   焦点: 模块: 2" "Repo: example/repo" "Section line")
    [[ "$output" == *"VPS-Kit MCP"* ]]
    [[ "$output" == *"Toolkit subtitle"* ]]
    [[ "$output" == *"主题: 紧凑风格   |   焦点: 模块: 2"* ]]
    [[ "$output" == *"Repo: example/repo"* ]]
    [[ "$output" == *"Section line"* ]]
  '
	[ "$status" -eq 0 ]
}

@test "ui_render_main_menu_hero 在 retro-launcher 下输出 ASCII hero 与上下文" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="retro-launcher"
    output=$(ui_render_main_menu_hero "VPS-Kit MCP" "Toolkit subtitle" "主题: 启动器风格   |   焦点: 模块: 5" "Repo: example/repo" "Core line")
    [[ "$output" == *"Toolkit subtitle"* ]]
    [[ "$output" == *"██╗   ██╗"* ]]
    [[ "$output" == *"VPS-Kit MCP"* ]]
    [[ "$output" == *"主题: 启动器风格   |   焦点: 模块: 5"* ]]
    [[ "$output" == *"Repo: example/repo"* ]]
    [[ "$output" == *"Core line"* ]]
  '
	[ "$status" -eq 0 ]
}

@test "utils.sh 单独提供菜单 schema registry 与 UI 文案读取 helper" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    CONFIG_PATH=$(mktemp /tmp/utils.menu.registry.XXXXXX.json)
    cat >"$CONFIG_PATH" <<"JSON"
{
  "menus": {
    "THEME_MENU": {
      "ui": {
        "status_markers": {
          "current": "Selected"
        }
      }
    },
    "CUSTOM_MENU": {
      "ui": {
        "subtitle": "Custom subtitle",
        "focus": {
          "key": "scope",
          "value": "Edge"
        }
      }
    }
  }
}
JSON
    JB_UI_THEME="retro-launcher"
    [ "$(menu_schema_default MAIN_MENU text subtitle)" = "管理 Docker、Nginx、证书、常用工具和 MCP" ]
    [ "$(menu_ui_text_field CUSTOM_MENU subtitle)" = "Custom subtitle" ]
    [ "$(menu_ui_group_label MCP_MENU runtime)" = "运行状态" ]
    [ "$(menu_ui_status_marker THEME_MENU current)" = "Selected" ]
    [ "$(menu_ui_focus_key CUSTOM_MENU default)" = "scope" ]
    [ "$(menu_resolved_focus_value CUSTOM_MENU)" = "Edge" ]
  '
	[ "$status" -eq 0 ]
}

@test "utils.sh 提供模块页 header schema 默认值与共享 panel header helper" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    JB_UI_THEME="retro-launcher"
    [ "$(menu_schema_default DOCKER_MENU text subtitle)" = "管理 Docker 运行环境、服务状态和清理操作" ]
    [ "$(menu_schema_default CERT_MAINTENANCE_MENU text hint)" = "请选择续期、策略或诊断相关操作。" ]
    [ "$(menu_ui_focus_key NGINX_MENU)" = "入口" ]
    [ "$(menu_resolved_focus_value BBR_KERNEL_MENU)" = "内核" ]
    lines=()
    ui_append_schema_panel_header lines "WATCHTOWER_MENU" "Running"
    [ "${lines[0]}" = "管理容器自动更新、通知和运行状态" ]
    [ "${lines[1]}" = "主题: 启动器风格   |   焦点: 通用: Running" ]
    [ "${lines[2]}" = "请选择自动更新、通知或诊断相关操作。" ]
  '
	[ "$status" -eq 0 ]
}

@test "utils.sh 提供模块页 section schema 默认值与共享 page block helper" {
	run bash -c '
    set -euo pipefail
    source "$REPO_ROOT/utils.sh"
    CONFIG_PATH=$(mktemp /tmp/utils.menu.section.XXXXXX.json)
    cat >"$CONFIG_PATH" <<"JSON"
{
  "menus": {
    "DOCKER_MENU": {
      "ui": {
        "sections": {
          "runtime_overview": "Runtime Deck"
        }
      }
    }
  }
}
JSON
    JB_UI_THEME="retro-launcher"
    [ "$(menu_schema_default BBR_MENU section profile_control)" = "模式设置" ]
    [ "$(menu_schema_default NGINX_MENU section operations_policy)" = "运行与策略" ]
    [ "$(menu_ui_section_label DOCKER_MENU runtime_overview)" = "Runtime Deck" ]
    lines=()
    ui_append_schema_page_block lines "DOCKER_MENU" "runtime_overview" "Item A"
    [ -z "${lines[0]}" ]
    [[ "${lines[1]}" == *"Runtime Deck"* ]]
    [ -z "${lines[2]}" ]
    [ "${lines[3]}" = "Item A" ]
  '
	[ "$status" -eq 0 ]
}

@test "README 说明逻辑菜单 ID 也可直接覆盖模块页 UI" {
	run bash -c '
    set -euo pipefail
    readme="$1"
    grep -F "DOCKER_INSTALL_MENU" "$readme" >/dev/null
    grep -F "DOCKER_BOOTSTRAP_MENU" "$readme" >/dev/null
    grep -F "CERT_MAINTENANCE_MENU" "$readme" >/dev/null
    grep -F "BBR_KERNEL_MENU" "$readme" >/dev/null
    grep -F "menus.<MENU>.ui" "$readme" >/dev/null
  ' _ "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
}

@test "README 提供逻辑菜单 ID 一览表" {
	run bash -c '
    set -euo pipefail
    readme="$1"
	    grep -F "`DOCKER_MENU` | Docker 已安装主菜单" "$readme" >/dev/null
	    grep -F "`WATCHTOWER_MENU` | Watchtower 主菜单" "$readme" >/dev/null
	    grep -F "`BBR_KERNEL_MENU` | BBR 内核维护页" "$readme" >/dev/null
	    grep -F "`NGINX_MENU` | Nginx 主菜单" "$readme" >/dev/null
  ' _ "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
}
