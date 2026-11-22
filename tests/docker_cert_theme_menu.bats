#!/usr/bin/env bats

setup() {
	export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "docker render_docker_main_menu 在 retro-launcher 下输出分区式菜单" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/docker.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" "$REPO_ROOT/docker.sh" | sed "\$d" >"$script_copy"
    source "$script_copy"
    source "$REPO_ROOT/utils.sh"
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    DOCKER_INSTALLED="true"
    DOCKER_SERVICE_STATUS="active"
    DOCKER_VERSION="Docker version 27.0.1"
    COMPOSE_VERSION="v2.29.1"
    render_docker_main_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Docker"* ]]
	[[ "$output" == *"当前状态"* ]]
	[[ "$output" == *"常用操作"* ]]
	[[ "$output" == *"进阶操作"* ]]
	[[ "$output" == *"危险操作"* ]]
	[[ "$output" == *"修复服务状态"* ]]
}

@test "docker render_manage_installation_menu 在 retro-launcher 下复用 schema panel header" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/docker.install.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" "$REPO_ROOT/docker.sh" | sed "\$d" >"$script_copy"
    source "$script_copy"
    source "$REPO_ROOT/utils.sh"
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    render_manage_installation_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"安装管理"* ]]
	[[ "$output" == *"主题: 启动器风格   |   焦点: 范围: 重装与卸载"* ]]
	[[ "$output" == *"请选择重新安装或卸载 Docker。"* ]]
	[[ "$output" == *"重装与卸载"* ]]
}

@test "cert render_cert_main_menu 在 retro-launcher 下输出分区式菜单" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/cert.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" "$REPO_ROOT/cert.sh" | sed "\$d" >"$script_copy"
    source "$script_copy"
    source "$REPO_ROOT/utils.sh"
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    ACME_BIN="/tmp/not-installed-acme.sh"
    render_cert_main_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"证书管理"* ]]
	[[ "$output" == *"当前状态"* ]]
	[[ "$output" == *"常用操作"* ]]
	[[ "$output" == *"诊断与策略"* ]]
	[[ "$output" == *"申请证书"* ]]
	[[ "$output" == *"系统设置"* ]]
}

@test "cert render_cert_system_maintenance_menu 在 retro-launcher 下复用 schema panel header" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/cert.maintenance.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" "$REPO_ROOT/cert.sh" | sed "\$d" >"$script_copy"
    source "$script_copy"
    source "$REPO_ROOT/utils.sh"
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    render_cert_system_maintenance_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"系统维护"* ]]
	[[ "$output" == *"主题: 启动器风格   |   焦点: 范围: 续期"* ]]
	[[ "$output" == *"先检查当前状态，再决定是否升级或调整策略。"* ]]
	[[ "$output" == *"诊断与升级"* ]]
	[[ "$output" == *"策略设置"* ]]
}
