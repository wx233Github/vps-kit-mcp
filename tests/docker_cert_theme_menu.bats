#!/usr/bin/env bats

@test "docker render_docker_main_menu 在 retro-launcher 下输出分区式菜单" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/docker.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" /root/aa/vps-kit-mcp/docker.sh | sed "\$d" >"$script_copy"
    source "$script_copy"
    source /root/aa/vps-kit-mcp/utils.sh
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    DOCKER_INSTALLED="true"
    DOCKER_SERVICE_STATUS="active"
    DOCKER_VERSION="Docker version 27.0.1"
    COMPOSE_VERSION="v2.29.1"
    render_docker_main_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Provision Docker engine, manage Compose runtime and recover service lifecycle safely"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Runtime: Ready"* ]]
	[[ "$output" == *"Runtime Overview"* ]]
	[[ "$output" == *"Action Center"* ]]
	[[ "$output" == *"Recovery & Lifecycle"* ]]
	[[ "$output" == *"快速修复服务状态"* ]]
}

@test "docker render_manage_installation_menu 在 retro-launcher 下复用 schema panel header" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/docker.install.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" /root/aa/vps-kit-mcp/docker.sh | sed "\$d" >"$script_copy"
    source "$script_copy"
    source /root/aa/vps-kit-mcp/utils.sh
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    render_manage_installation_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Provision Docker engine, manage Compose runtime and recover service lifecycle safely"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Scope: Lifecycle"* ]]
	[[ "$output" == *"Choose whether to rebuild the runtime stack or retire the current installation."* ]]
	[[ "$output" == *"Recovery & Lifecycle"* ]]
}

@test "cert render_cert_main_menu 在 retro-launcher 下输出分区式菜单" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/cert.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" /root/aa/vps-kit-mcp/cert.sh | sed "\$d" >"$script_copy"
    source "$script_copy"
    source /root/aa/vps-kit-mcp/utils.sh
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    ACME_BIN="/tmp/not-installed-acme.sh"
    render_cert_main_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Issue TLS certificates, inspect renewal health and keep acme workflows reliable"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Service: acme.sh Missing"* ]]
	[[ "$output" == *"Certificate Overview"* ]]
	[[ "$output" == *"Issue & Renew"* ]]
	[[ "$output" == *"Policy Control"* ]]
	[[ "$output" == *"系统设置"* ]]
}

@test "cert render_cert_system_maintenance_menu 在 retro-launcher 下复用 schema panel header" {
	run bash -c '
    set -euo pipefail
    script_copy=$(mktemp /tmp/cert.maintenance.theme.menu.XXXXXX.sh)
    awk "/^UTILS_PATH=/ {print \"UTILS_PATH=\\\"/tmp/__missing_utils__\\\"\"; next} {print}" /root/aa/vps-kit-mcp/cert.sh | sed "\$d" >"$script_copy"
    source "$script_copy"
    source /root/aa/vps-kit-mcp/utils.sh
    rm -f "$script_copy"
    JB_UI_THEME="retro-launcher"
    render_cert_system_maintenance_menu
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"Issue TLS certificates, inspect renewal health and keep acme workflows reliable"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Scope: Renewal"* ]]
	[[ "$output" == *"Adjust renewal policy, verify cron health and keep acme.sh updated."* ]]
	[[ "$output" == *"Diagnostics"* ]]
	[[ "$output" == *"Policy Control"* ]]
}
