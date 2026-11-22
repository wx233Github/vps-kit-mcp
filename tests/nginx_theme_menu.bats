#!/usr/bin/env bats

setup() {
	export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
}

@test "nginx main_menu 在 retro-launcher 下输出分区式菜单" {
	tmp_script=$(mktemp /tmp/nginx.theme.menu.exec.XXXXXX.sh)
	cat >"$tmp_script" <<'EOF'
set -euo pipefail
source "$REPO_ROOT/utils.sh"
source "$REPO_ROOT/lib/nginx_core.sh"
source "$REPO_ROOT/lib/nginx_flow.sh"

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
_nginx_config_health_status() { printf '%s' "正常"; }
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
	[[ "$output" == *"当前状态"* ]]
	[[ "$output" == *"常用操作"* ]]
	[[ "$output" == *"诊断与策略"* ]]
	[[ "$output" == *"配置新网站"* ]]
	[[ "$output" == *"Cloudflare 防御"* ]]
	[[ "$output" == *"修复多实例冲突"* ]]
	[[ "$output" == *"共享组 + pid 隔离"* ]]
}
