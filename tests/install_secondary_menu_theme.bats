#!/usr/bin/env bats

setup() {
	export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "render_secondary_menu 在 retro-launcher 下输出分组与描述" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.secondary.menu.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    JB_UI_THEME="retro-launcher"
    primary_items=(
      "🔄|Watchtower|item|tools/Watchtower.sh|Docker 容器自动更新与巡检入口|automation"
      "⚡|BBR ACE|item|tools/bbr_ace.sh|网络拥塞控制优化与内核调优助手|network"
    )
    func_items=()
    _get_watchtower_status() { printf "%s" "enabled"; }
    render_secondary_menu "TOOLS_MENU" "🛠️ 常用工具" primary_items func_items
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"自动化"* ]]
	[[ "$output" == *"网络"* ]]
	[[ "$output" == *"Docker 容器自动更新与巡检入口"* ]]
	[[ "$output" == *"[enabled]"* ]]
	[[ "$output" == *"管理自动更新和网络调优工具"* ]]
	[[ "$output" == *"主题: 启动器风格"* ]]
	[[ "$output" == *"请选择要管理的工具。"* ]]
}

@test "render_secondary_menu 在 classic 下保持紧凑列表" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.secondary.classic.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    JB_UI_THEME="classic"
    primary_items=(
      "🔄|Watchtower|item|tools/Watchtower.sh|Docker 容器自动更新与巡检入口|automation"
    )
    func_items=()
    render_secondary_menu "TOOLS_MENU" "🛠️ 常用工具" primary_items func_items
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"1. 🔄 Watchtower"* ]]
	[[ "$output" != *"Operational add-ons for container updates and network tuning"* ]]
	[[ "$output" != *"Automation"* ]]
	[[ "$output" != *"Docker 容器自动更新与巡检入口"* ]]
}

@test "render_secondary_menu 在 THEME_MENU 下输出当前主题 header" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.secondary.theme.center.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    JB_UI_THEME="compact"
    primary_items=()
    func_items=(
      "🚀|Retro Launcher|func|set_theme_retro_launcher|大标题启动器首页 + 分区式产品子页|profiles"
      "📦|Compact|func|set_theme_compact|更紧凑的工具台布局，适合小终端窗口|profiles"
    )
    render_secondary_menu "THEME_MENU" "🎛️ Theme Center" primary_items func_items
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"主题方案"* ]]
	[[ "$output" == *"Retro Launcher"* ]]
	[[ "$output" == *"[当前]"* ]]
	[[ "$output" == *"切换界面样式，选择适合当前终端的显示方式"* ]]
	[[ "$output" == *"焦点: 当前: "* ]]
}

@test "render_secondary_menu 从 config 读取 subtitle hint focus 与分组标题" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.secondary.config.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    CONFIG_PATH=$(mktemp /tmp/install.secondary.config.menu.XXXXXX.json)
    cat >"$CONFIG_PATH" <<"JSON"
{
  "menus": {
    "CUSTOM_MENU": {
      "ui": {
        "subtitle": "Custom subtitle",
        "hint": "Custom hint",
        "focus": {
          "key": "scope",
          "value": "Edge"
        },
        "groups": {
          "ops": "Ops Lane"
        }
      }
    }
  }
}
JSON
    JB_UI_THEME="retro-launcher"
    primary_items=(
      "🧪|Custom Item|item|custom.sh|自定义描述|ops"
    )
    func_items=()
    render_secondary_menu "CUSTOM_MENU" "Custom Menu" primary_items func_items
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Custom Menu"* ]]
	[[ "$output" == *"Ops Lane"* ]]
	[[ "$output" == *"🧪 Custom Item"* ]]
	[[ "$output" == *"自定义描述"* ]]
}

@test "render_secondary_menu 在 classic 下复用统一收集逻辑并保留状态" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.secondary.classic.shared.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    JB_UI_THEME="classic"
    primary_items=(
      "🔄|Watchtower|item|tools/Watchtower.sh|Docker 容器自动更新与巡检入口|automation"
    )
    func_items=(
      "🚀|Retro Launcher|func|set_theme_retro_launcher|大标题启动器首页 + 分区式产品子页|profiles"
    )
    _get_watchtower_status() { printf "%s" "enabled"; }
    render_secondary_menu "TOOLS_MENU" "🛠️ 常用工具" primary_items func_items
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"1. 🔄 Watchtower [enabled]"* ]]
	[[ "$output" == *"a. 🚀 Retro Launcher"* ]]
	[[ "$output" != *"Docker 容器自动更新与巡检入口"* ]]
}

@test "render_main_menu 在 retro-launcher 下输出三大分组与状态" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.main.menu.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    JB_UI_THEME="retro-launcher"
    SCRIPT_VERSION="v9.9.9-test"
    get_startup_update_mode() { printf "%s" "background"; }
    _get_docker_status() { printf "%s" "active"; }
    _get_nginx_status() { printf "%s" "installed"; }
    _get_watchtower_status() { printf "%s" "enabled"; }
    primary_items=(
      "🐳|Docker|item|docker.sh|安装 Docker / Compose 与运行环境管理|core"
      "🛠️|常用工具|submenu|TOOLS_MENU|Watchtower 与 BBR ACE 工具集|tools"
      "🎛️|Theme Center|submenu|THEME_MENU|切换终端主题与查看当前界面风格|system"
    )
    func_items=(
      "🔁|更新切换|func|toggle_startup_update_mode|切换启动检查更新模式|system"
    )
    render_main_menu "{}" "VPS-Kit MCP" primary_items func_items
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"管理 Docker、Nginx、证书、常用工具和 MCP"* ]]
	[[ "$output" == *"版本: v9.9.9-test   |   主题: 启动器风格   |   更新: 后台"* ]]
	[[ "$output" == *"核心功能"* ]]
	[[ "$output" == *"工具"* ]]
	[[ "$output" == *"系统"* ]]
	[[ "$output" == *"[active]"* ]]
	[[ "$output" == *"[当前]"* ]]
	[[ "$output" == *"[后台]"* ]]
}

@test "render_main_menu 从 config 读取首页 subtitle repo meta 与分组标题" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.main.config.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    CONFIG_PATH=$(mktemp /tmp/install.main.config.menu.XXXXXX.json)
    cat >"$CONFIG_PATH" <<"JSON"
{
  "menus": {
    "MAIN_MENU": {
      "ui": {
        "subtitle": "Custom main subtitle",
        "repo": "Repo: example/custom",
        "meta_labels": {
          "version": "Build",
          "theme": "Skin",
          "update": "Refresh"
        },
        "groups": {
          "core": "Core Lane",
          "tools": "Utility Deck",
          "system": "Control Room"
        }
      }
    }
  }
}
JSON
    JB_UI_THEME="retro-launcher"
    SCRIPT_VERSION="v1.2.3-custom"
    get_startup_update_mode() { printf "%s" "legacy"; }
    _get_docker_status() { printf "%s" "active"; }
    primary_items=(
      "🐳|Docker|item|docker.sh|安装 Docker / Compose 与运行环境管理|core"
      "🛠️|常用工具|submenu|TOOLS_MENU|Watchtower 与 BBR ACE 工具集|tools"
      "🎛️|Theme Center|submenu|THEME_MENU|切换终端主题与查看当前界面风格|system"
    )
    func_items=()
    render_main_menu "{}" "VPS-Kit MCP" primary_items func_items
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Custom main subtitle"* ]]
	[[ "$output" == *"Build: v1.2.3-custom   |   Skin: 启动器风格   |   Refresh: 前台"* ]]
	[[ "$output" == *"Repo: example/custom"* ]]
	[[ "$output" == *"Core Lane"* ]]
	[[ "$output" == *"Utility Deck"* ]]
	[[ "$output" == *"Control Room"* ]]
}

@test "menu_status_text 输出状态值并遵循 config 标记" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.status.config.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    CONFIG_PATH=$(mktemp /tmp/install.status.config.menu.XXXXXX.json)
    cat >"$CONFIG_PATH" <<"JSON"
{
  "menus": {
    "MAIN_MENU": {
      "ui": {
        "status_labels": {
          "docker.sh": "Engine",
          "THEME_MENU": "Profile",
          "toggle_startup_update_mode": "Update Track"
        }
      }
    },
    "TOOLS_MENU": {
      "ui": {
        "status_labels": {
          "tools/Watchtower.sh": "Auto Ops"
        }
      }
    },
    "THEME_MENU": {
      "ui": {
        "status_markers": {
          "current": "Selected"
        }
      }
    }
  }
}
JSON
    JB_UI_THEME="retro-launcher"
    _get_docker_status() { printf "%s" "healthy"; }
    _get_watchtower_status() { printf "%s" "enabled"; }
    get_startup_update_mode() { printf "%s" "background"; }
    [ "$(menu_status_text MAIN_MENU docker.sh)" = "healthy" ]
    [ "$(menu_status_text MAIN_MENU THEME_MENU)" = "当前" ]
    [ "$(menu_status_text MAIN_MENU toggle_startup_update_mode)" = "后台" ]
    [ "$(menu_status_text TOOLS_MENU tools/Watchtower.sh)" = "enabled" ]
    [ "$(menu_status_text THEME_MENU set_theme_retro_launcher)" = "Selected" ]
  '
	[ "$status" -eq 0 ]
}

@test "menu schema default registry 为未配置菜单提供稳定默认词表" {
	run bash -c '
    set -euo pipefail
    install_lib=$(mktemp /tmp/install.schema.default.XXXXXX.sh)
    sed "\$d" "$REPO_ROOT/install.sh" >"$install_lib"
    readlink() { printf "%s\n" "/opt/vps_install_modules/install.sh"; }
    source() {
      if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
        builtin source "$REPO_ROOT/utils.sh"
        return 0
      fi
      builtin source "$1"
    }
    builtin source "$install_lib"
    rm -f "$install_lib"
    JB_UI_THEME="retro-launcher"
    [ "$(menu_ui_text_field UNKNOWN_MENU subtitle)" = "管理当前模块的常用操作和状态" ]
    [ "$(menu_ui_text_field MAIN_MENU repo)" = "项目地址: https://github.com/wx233Github/vps-kit-mcp" ]
    [ "$(menu_ui_meta_label MAIN_MENU version)" = "版本" ]
    [ "$(menu_ui_status_label MAIN_MENU docker.sh)" = "Docker" ]
    [ "$(menu_ui_status_marker THEME_MENU current)" = "当前" ]
    [ "$(menu_ui_group_label MCP_MENU runtime)" = "运行状态" ]
    [ "$(menu_ui_focus_key TOOLS_MENU)" = "modules" ]
    [ "$(menu_ui_group_label THEME_MENU profiles)" = "主题方案" ]
    [ "$(menu_ui_focus_source THEME_MENU)" = "current_theme" ]
    [ "$(menu_resolved_focus_value THEME_MENU)" = "启动器风格" ]
  '
	[ "$status" -eq 0 ]
}
