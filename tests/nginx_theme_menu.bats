#!/usr/bin/env bats

@test "nginx main_menu 在 retro-launcher 下输出分区式菜单" {
	tmp_script=$(mktemp /tmp/nginx.theme.menu.exec.XXXXXX.sh)
	cat >"$tmp_script" <<'EOF'
set -euo pipefail
source "/root/aa/vps-kit-mcp/utils.sh"
source "/root/aa/vps-kit-mcp/lib/nginx_core.sh"
source "/root/aa/vps-kit-mcp/lib/nginx_flow.sh"

JB_UI_THEME="retro-launcher"
PURPLE=""
BRIGHT_RED=""
BOLD=""
NC=""
LOG_LEVEL_DEFAULT="INFO"
TMP_PAYLOAD_FILES=()
IS_INTERACTIVE_MODE="true"
LOCK_FILE_HTTP=""
LOCK_FILE_TCP=""
LOCK_FILE_CERT=""
LOCK_FILE_PROJECT=""
LOCK_FILE_LOGROTATE=""
LOCK_FILE_CRON=""
LOCK_FILE_CF=""
LOCK_FILE_WAL=""

_generate_op_id() { :; }
_ensure_menu_interactive() { return 0; }
_draw_dashboard() { :; }
prompt_menu_choice() { printf '%s\n' ""; return 0; }
_render_menu() {
  printf '%s\n' "$1"
  shift
  printf '%s\n' "$@"
}

main_menu
EOF
	run /bin/bash "$tmp_script"
	rm -f "$tmp_script"
	[ "$status" -eq 10 ]
	[[ "$output" == *"Nginx 管理"* ]]
	[[ "$output" == *"Coordinate edge routing, certificate ops and traffic defense for web entrypoints"* ]]
	[[ "$output" == *"Theme: Retro Launcher   |   Focus: Plane: Edge Gateway"* ]]
	[[ "$output" == *"Configure sites, TCP forwarding, defense posture and lifecycle operations."* ]]
	[[ "$output" == *"HTTP(S) Workloads"* ]]
	[[ "$output" == *"Transport Routing"* ]]
	[[ "$output" == *"Operations & Policy"* ]]
	[[ "$output" == *"Cloudflare 防御中心"* ]]
}
