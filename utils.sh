#!/usr/bin/env bash
# =============================================================
# 🚀 通用工具函数库 (v0.0.1)
# - 优化: generate_line 移除 sed 依赖，使用 Bash 原生字符串替换，提升性能。
# - 恢复: UI 输出回到标准流，日志保持在错误流。
# =============================================================

# --- 严格模式 ---
set -euo pipefail
IFS=$'\n\t'
export PATH='/usr/local/bin:/usr/bin:/bin'

# --- 默认配置 ---
DEFAULT_BASE_URL="https://raw.githubusercontent.com/wx233Github/vps-kit-mcp/main"
DEFAULT_INSTALL_DIR="/opt/vps_install_modules"
DEFAULT_BIN_DIR="/usr/local/bin"
DEFAULT_LOCK_FILE="/tmp/vps_install_modules.lock"
DEFAULT_TIMEZONE="Asia/Shanghai"
DEFAULT_CONFIG_PATH="${DEFAULT_INSTALL_DIR}/config.json"
DEFAULT_LOG_WITH_TIMESTAMP="false"
DEFAULT_LOG_FILE="/var/log/vps-kit-mcp-utils.log"
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_ENABLE_AUTO_UPDATE="true"
DEFAULT_NONINTERACTIVE="false"
DEFAULT_UI_THEME="retro-launcher"
DEFAULT_FORCE_RETRO_HERO="false"
# shellcheck disable=SC2034
DEFAULT_TTY_PATH="/dev/tty"
# shellcheck disable=SC2034
DEFAULT_CLEAR_MODE="off"

readonly -a UTILS_PUBLIC_API=(
	"log_info"
	"log_success"
	"log_warn"
	"log_err"
	"log_debug"
	"die"
	"check_dependencies"
	"validate_args"
	"_prompt_user_input"
	"_prompt_for_menu_choice"
	"press_enter_to_continue"
	"confirm_action"
	"normalize_clear_mode"
	"should_clear_screen"
	"load_config"
	"get_ui_theme"
	"ui_theme_label"
	"menu_vocab_phrase"
	"menu_schema_default"
	"menu_ui_text_field"
	"menu_ui_meta_label"
	"menu_ui_status_label"
	"menu_ui_status_marker"
	"menu_ui_group_label"
	"menu_ui_section_label"
	"menu_group_heading"
	"menu_ui_focus_key"
	"menu_ui_focus_value"
	"menu_ui_focus_source"
	"menu_resolved_focus_value"
	"ui_append_schema_panel_header"
	"ui_append_schema_or_fallback_panel_header"
	"ui_append_schema_page_block"
	"ui_append_schema_or_fallback_page_block"
	"ui_define_manual_fallback_helpers"
	"ui_define_meta_fallback_helpers"
	"ui_append_manual_panel_fallback"
	"ui_append_manual_page_block"
	"ui_meta_focus_fallback_line"
	"ui_meta_focus_label"
	"ui_meta_focus_line"
	"ui_append_context_lines"
	"ui_append_panel_header"
	"ui_append_main_menu_context"
	"ui_append_page_block"
	"generate_line"
	"_get_visual_width"
	"_render_menu"
	"ui_render_main_menu_hero"
	"ui_format_section_heading"
	"utils_api_contract"
)

# --- 颜色定义 ---
if [ -t 1 ] || [ "${FORCE_COLOR:-}" = "true" ]; then
	# shellcheck disable=SC2034
	RED=$'\033[0;31m'
	GREEN=$'\033[0;32m'
	YELLOW=$'\033[0;33m'
	# shellcheck disable=SC2034
	BLUE=$'\033[0;34m'
	# shellcheck disable=SC2034
	CYAN=$'\033[0;36m'
	GRAY=$'\033[2m'
	NC=$'\033[0m'
	BOLD=$'\033[1m'
	ORANGE=$'\033[38;5;208m' # 橙色 #FA720A
else
	# shellcheck disable=SC2034
	RED=""
	GREEN=""
	YELLOW=""
	# shellcheck disable=SC2034
	BLUE=""
	# shellcheck disable=SC2034
	CYAN=""
	GRAY=""
	NC=""
	BOLD=""
	ORANGE=""
fi

# --- 日志系统 ---
_log_level_value() {
	local level="$1"
	case "$level" in
	DEBUG) printf '%s' "10" ;;
	INFO) printf '%s' "20" ;;
	WARN) printf '%s' "30" ;;
	ERROR) printf '%s' "40" ;;
	*) printf '%s' "20" ;;
	esac
}

_log_should_print() {
	local msg_level="$1"
	local current_level="${LOG_LEVEL:-${DEFAULT_LOG_LEVEL}}"
	local msg_value
	local cur_value
	msg_value="$(_log_level_value "$msg_level")"
	cur_value="$(_log_level_value "$current_level")"
	if [ "$msg_value" -ge "$cur_value" ]; then
		return 0
	fi
	return 1
}

_log_timestamp() {
	date +'%Y-%m-%d %H:%M:%S'
}

_log_write() {
	local level="$1"
	shift
	local msg="$*"
	local ts
	local log_file="${LOG_FILE:-${DEFAULT_LOG_FILE}}"
	ts="$(_log_timestamp)"
	if ! _log_should_print "$level"; then
		return 0
	fi
	if [ -n "$log_file" ]; then
		printf '[%s] [%s] %s\n' "$ts" "$level" "$msg" >>"$log_file" 2>/dev/null || true
	fi
	printf '[%s] %b\n' "$level" "$msg"
}

log_info() { _log_write "INFO" "$*"; }
log_success() { _log_write "INFO" "$*"; }
log_warn() { _log_write "WARN" "$*" >&2; }
log_err() { _log_write "ERROR" "$*" >&2; }
log_debug() { if [ "${JB_DEBUG_MODE:-false}" = "true" ]; then _log_write "DEBUG" "$*" >&2; fi; }

sanitize_noninteractive_flag() {
	case "${JB_NONINTERACTIVE:-false}" in
	true | false) return 0 ;;
	*)
		log_warn "JB_NONINTERACTIVE 值非法: ${JB_NONINTERACTIVE}，已回退为 false"
		JB_NONINTERACTIVE="false"
		return 0
		;;
	esac
}

utils_public_api() {
	printf '%s\n' "${UTILS_PUBLIC_API[@]}"
}

utils_api_contract() {
	printf '%s\n' "公共 API 稳定层（向后兼容承诺）:"
	printf '%s\n' "- 日志: log_info/log_warn/log_err/log_debug"
	printf '%s\n' "- 交互: _prompt_user_input/_prompt_for_menu_choice/confirm_action"
	printf '%s\n' "- UI: _render_menu/ui_render_main_menu_hero/ui_theme_label/menu_schema_default/menu_ui_text_field/menu_ui_meta_label/menu_ui_status_label/menu_ui_status_marker/menu_ui_group_label/menu_ui_section_label/menu_group_heading/menu_ui_focus_key/menu_ui_focus_value/menu_ui_focus_source/menu_resolved_focus_value/ui_append_schema_panel_header/ui_append_schema_or_fallback_panel_header/ui_append_schema_page_block/ui_append_schema_or_fallback_page_block/ui_define_manual_fallback_helpers/ui_define_meta_fallback_helpers/ui_append_manual_panel_fallback/ui_append_manual_page_block/ui_meta_focus_fallback_line/ui_meta_focus_label/ui_meta_focus_line/ui_append_context_lines/ui_append_panel_header/ui_append_main_menu_context/ui_append_page_block/press_enter_to_continue/should_clear_screen"
	printf '%s\n' "- 配置: load_config"
}

die() {
	local msg="$1"
	local code="${2:-1}"
	log_err "$msg"
	return "$code"
}

check_dependencies() {
	local missing=()
	local dep
	for dep in "$@"; do
		if ! command -v "$dep" >/dev/null 2>&1; then
			missing+=("$dep")
		fi
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		die "缺少依赖: ${missing[*]}" 127 || return "$?"
		return 127
	fi
	return 0
}

validate_args() {
	if [ "$#" -lt 3 ]; then
		return 0
	fi
	local min_args="$1"
	local max_args="$2"
	local actual_args="$3"
	if [ "$actual_args" -lt "$min_args" ] || [ "$actual_args" -gt "$max_args" ]; then
		die "参数数量不符合要求: 需要 ${min_args}-${max_args}，实际 ${actual_args}" 64 || return "$?"
		return 64
	fi
	return 0
}

# --- 交互函数 ---
_tty_available() {
	if [ ! -t 0 ] && [ ! -t 1 ]; then
		return 1
	fi
	[ -r "${JB_TTY_PATH:-/dev/tty}" ] && [ -w "${JB_TTY_PATH:-/dev/tty}" ]
}

_stdin_has_data() {
	if [ -t 0 ]; then
		return 0
	fi
	if read -r -t 0; then
		return 0
	fi
	return 1
}

_prompt_user_input() {
	local prompt_text="$1"
	local default_value="$2"
	local result
	local prompt_target

	if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
		log_warn "非交互模式：使用默认值"
		echo "$default_value"
		return 0
	fi
	if [ -t 1 ]; then
		prompt_target="/dev/stdout"
	elif _tty_available; then
		prompt_target="${JB_TTY_PATH:-/dev/tty}"
	else
		prompt_target="/dev/stderr"
	fi
	if [ -t 0 ]; then
		printf '%b' "${YELLOW}${prompt_text}${NC}" >"$prompt_target"
		read -r result
	elif _stdin_has_data; then
		read -r result
	elif _tty_available; then
		printf '%b' "${YELLOW}${prompt_text}${NC}" >"${JB_TTY_PATH:-/dev/tty}"
		read -r result <"${JB_TTY_PATH:-/dev/tty}"
	else
		printf '%b' "${YELLOW}${prompt_text}${NC}" >&2
		log_warn "无法访问 /dev/tty，使用默认值"
		echo "$default_value"
		return 0
	fi

	if [ -z "$result" ]; then
		echo "$default_value"
	else
		echo "$result"
	fi
}

_prompt_for_menu_choice() {
	local numeric_range="$1"
	local func_options="${2:-}"
	local context="${JB_MENU_CONTEXT:-submenu}"
	local prompt_text=""
	local prompt_target
	prompt_text=$(ui_build_prompt_text "$numeric_range" "$func_options" "$context")

	local choice
	if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
		log_warn "非交互模式：返回空选项"
		echo ""
		return 0
	fi
	if [ -t 1 ]; then
		prompt_target="/dev/stdout"
	elif _tty_available; then
		prompt_target="${JB_TTY_PATH:-/dev/tty}"
	else
		prompt_target="/dev/stderr"
	fi
	if [ -t 0 ]; then
		printf '%b' "$prompt_text" >"$prompt_target"
		read -r choice
		echo "$choice"
		return 0
	fi
	if _stdin_has_data; then
		read -r choice
		echo "$choice"
		return 0
	fi
	if _tty_available; then
		printf '%b' "$prompt_text" >"${JB_TTY_PATH:-/dev/tty}"
		if read -r choice <"${JB_TTY_PATH:-/dev/tty}"; then
			echo "$choice"
			return 0
		fi
	fi
	printf '%b' "$prompt_text" >&2
	log_warn "无法访问 /dev/tty，返回空选项"
	if [ "${JB_FORCE_REFRESH:-0}" = "1" ]; then
		echo "__JB_REFRESH__"
		return 0
	fi
	echo ""
	return 0
}

press_enter_to_continue() {
	local prompt_target
	if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
		log_warn "非交互模式：跳过等待"
		return 0
	fi
	if [ -t 1 ]; then
		prompt_target="/dev/stdout"
	elif _tty_available; then
		prompt_target="${JB_TTY_PATH:-/dev/tty}"
	else
		prompt_target="/dev/stderr"
	fi
	if [ -t 0 ]; then
		printf '%b' "\n${YELLOW}按 Enter 键继续...${NC}" >"$prompt_target"
		read -r
		return 0
	fi
	if _stdin_has_data; then
		read -r
		return 0
	fi
	if _tty_available; then
		printf '%b' "\n${YELLOW}按 Enter 键继续...${NC}" >"${JB_TTY_PATH:-/dev/tty}"
		read -r <"${JB_TTY_PATH:-/dev/tty}"
		return 0
	fi
	printf '%b' "\n${YELLOW}按 Enter 键继续...${NC}" >&2
	log_warn "无法访问 /dev/tty，跳过等待"
	return 0
}
confirm_action() {
	local prompt="$1"
	local choice
	local prompt_target
	if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
		log_warn "非交互模式：默认确认"
		return 0
	fi
	if [ -t 1 ]; then
		prompt_target="/dev/stdout"
	elif _tty_available; then
		prompt_target="${JB_TTY_PATH:-/dev/tty}"
	else
		prompt_target="/dev/stderr"
	fi
	if [ -t 0 ]; then
		printf '%b' "${YELLOW}${prompt} ([y]/n): ${NC}" >"$prompt_target"
		read -r choice
	elif _stdin_has_data; then
		read -r choice
	elif _tty_available; then
		printf '%b' "${YELLOW}${prompt} ([y]/n): ${NC}" >"${JB_TTY_PATH:-/dev/tty}"
		read -r choice <"${JB_TTY_PATH:-/dev/tty}"
	else
		printf '%b' "${YELLOW}${prompt} ([y]/n): ${NC}" >&2
		log_warn "无法访问 /dev/tty，默认确认"
		return 0
	fi
	case "$choice" in n | N) return 1 ;; *) return 0 ;; esac
}

confirm_destructive_action() {
	local action_desc="${1:-危险操作}"
	local impact_desc="${2:-该操作可能修改当前配置或服务状态。}"
	confirm_action "将执行：${action_desc}；影响：${impact_desc} 是否继续"
}

result_success() {
	local message="${1:-操作完成。}"
	log_success "已完成：${message}"
}

result_failure() {
	local message="${1:-操作失败。}"
	log_err "操作失败：${message}"
}

ui_theme_exists() {
	local theme="${1:-}"
	case "$theme" in
	classic | retro-launcher | compact | minimal) return 0 ;;
	*) return 1 ;;
	esac
}

get_ui_theme() {
	local theme="${JB_UI_THEME:-${UI_THEME:-${DEFAULT_UI_THEME}}}"
	if ! ui_theme_exists "$theme"; then
		theme="${DEFAULT_UI_THEME}"
	fi
	printf '%s' "$theme"
}

ui_force_retro_hero_enabled() {
	case "${JB_FORCE_RETRO_HERO:-${UI_FORCE_RETRO_HERO:-${DEFAULT_FORCE_RETRO_HERO}}}" in
	true | TRUE | 1 | yes | YES | on | ON) return 0 ;;
	*) return 1 ;;
	esac
}

ui_output_target() {
	if [ -t 1 ]; then
		printf '%s' "/proc/self/fd/1"
	elif _tty_available; then
		printf '%s' "${JB_TTY_PATH:-/dev/tty}"
	else
		printf '%s' "/proc/self/fd/1"
	fi
}

ui_strip_ansi() {
	printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

ui_repeat_char() {
	local len="${1:-0}"
	local char="${2:--}"
	if [ "$len" -le 0 ]; then
		printf ''
		return 0
	fi
	generate_line "$len" "$char"
}

ui_pad_right() {
	local text="${1:-}"
	local width="${2:-0}"
	if printf '%s' "$text" | LC_ALL=C grep -q '[^ -~]' 2>/dev/null; then
		printf ''
		return 0
	fi
	local current_width=0
	current_width=$(_get_visual_width "$text")
	if [ "$current_width" -ge "$width" ]; then
		printf ''
		return 0
	fi
	printf '%*s' $((width - current_width)) ''
}

ui_print_blank_line() {
	local out="${1:-$(ui_output_target)}"
	case "$out" in
	/proc/self/fd/1 | /dev/stdout | /dev/fd/1)
		printf '\n'
		;;
	*)
		printf '\n' >"$out"
		;;
	esac
}

ui_print_line() {
	local out="$1"
	shift
	case "$out" in
	/proc/self/fd/1 | /dev/stdout | /dev/fd/1)
		printf '%b\n' "$*"
		;;
	*)
		printf '%b\n' "$*" >"$out"
		;;
	esac
}

ui_menu_footer_text() {
	local context="${1:-submenu}"
	case "$context" in
	main)
		printf '%s' '请输入编号，直接回车退出。'
		;;
	*)
		printf '%s' '请输入编号，直接回车返回。'
		;;
	esac
}

ui_format_section_heading() {
	local text="${1:-Section}"
	local theme
	theme=$(get_ui_theme)
	case "$theme" in
	minimal)
		printf '%s' "$text"
		;;
	*)
		printf '%b' "${CYAN}${text}${NC}"
		;;
	esac
}

ui_theme_label() {
	local theme="${1:-$(get_ui_theme)}"
	case "$theme" in
	retro-launcher) printf '%s' "启动器风格" ;;
	classic) printf '%s' "经典风格" ;;
	compact) printf '%s' "紧凑风格" ;;
	minimal) printf '%s' "极简风格" ;;
	*) printf '%s' "$theme" ;;
	esac
}

menu_vocab_phrase() {
	case "${1:-}" in
	label_version) printf '%s' "版本" ;;
	label_theme) printf '%s' "主题" ;;
	label_update) printf '%s' "更新" ;;
	label_docker) printf '%s' "Docker" ;;
	label_nginx) printf '%s' "Nginx" ;;
	label_watchtower) printf '%s' "Watchtower" ;;
	label_current_cn) printf '%s' "当前" ;;
	label_mode_cn) printf '%s' "方式" ;;
	marker_current) printf '%s' "当前" ;;
	headline_main_subtitle) printf '%s' "管理 Docker、Nginx、证书、常用工具和 MCP" ;;
	headline_tools_subtitle) printf '%s' "管理自动更新和网络调优工具" ;;
	headline_mcp_subtitle) printf '%s' "管理 PTY 会话和 MCP 相关工具" ;;
	headline_theme_subtitle) printf '%s' "切换界面样式，选择适合当前终端的显示方式" ;;
	headline_docker_subtitle) printf '%s' "管理 Docker 运行环境、服务状态和清理操作" ;;
	headline_cert_subtitle) printf '%s' "申请证书、续期证书并检查当前状态" ;;
	headline_watchtower_subtitle) printf '%s' "管理容器自动更新、通知和运行状态" ;;
	headline_bbr_subtitle) printf '%s' "管理网络调优、拥塞控制和内核相关设置" ;;
	headline_bbr_kernel_subtitle) printf '%s' "处理内核升级、回退和清理操作" ;;
	headline_nginx_subtitle) printf '%s' "管理网站代理、证书、TCP 转发和运行状态" ;;
	headline_generic_subtitle) printf '%s' "管理当前模块的常用操作和状态" ;;
	hint_tools) printf '%s' "请选择要管理的工具。" ;;
	hint_mcp) printf '%s' "请选择要管理的 PTY 或 MCP 工具。" ;;
	hint_theme) printf '%s' "请选择适合当前终端的界面主题。" ;;
	hint_docker) printf '%s' "先看当前状态，再选择需要执行的操作。" ;;
	hint_docker_bootstrap) printf '%s' "当前尚未安装 Docker，请先完成安装。" ;;
	hint_docker_install) printf '%s' "请选择重新安装或卸载 Docker。" ;;
	hint_cert) printf '%s' "请选择证书申请、续期或诊断操作。" ;;
	hint_cert_maintenance) printf '%s' "请选择续期、策略或诊断相关操作。" ;;
	hint_watchtower) printf '%s' "请选择自动更新、通知或诊断相关操作。" ;;
	hint_bbr) printf '%s' "请选择网络调优、内核管理或恢复操作。" ;;
	hint_bbr_kernel) printf '%s' "请选择内核升级、回退或清理操作。" ;;
	hint_nginx) printf '%s' "请选择网站、证书、TCP 转发或修复操作。" ;;
	hint_generic) printf '%s' "请选择要执行的操作。" ;;
	repo_default) printf '%s' "项目地址: https://github.com/wx233Github/vps-kit-mcp" ;;
	heading_core_modules) printf '%s' "核心功能" ;;
	heading_tools) printf '%s' "工具" ;;
	heading_system) printf '%s' "系统" ;;
	heading_automation) printf '%s' "自动化" ;;
	heading_networking) printf '%s' "网络" ;;
	heading_runtime) printf '%s' "运行状态" ;;
	heading_tooling) printf '%s' "工具" ;;
	heading_theme_profiles) printf '%s' "主题方案" ;;
	heading_general) printf '%s' "通用" ;;
	heading_runtime_overview) printf '%s' "当前状态" ;;
	heading_action_center) printf '%s' "常用操作" ;;
	heading_recovery_lifecycle) printf '%s' "重装与卸载" ;;
	heading_bootstrap_overview) printf '%s' "当前状态" ;;
	heading_launch_pad) printf '%s' "开始安装" ;;
	heading_certificate_overview) printf '%s' "证书状态" ;;
	heading_issue_renew) printf '%s' "申请与续期" ;;
	heading_policy_control) printf '%s' "策略设置" ;;
	heading_diagnostics) printf '%s' "诊断排查" ;;
	heading_service_overview) printf '%s' "服务状态" ;;
	heading_profile_control) printf '%s' "模式设置" ;;
	heading_http_workloads) printf '%s' "网站与代理" ;;
	heading_transport_routing) printf '%s' "TCP 转发" ;;
	heading_operations_policy) printf '%s' "运行与策略" ;;
	focus_key_modules) printf '%s' "模块数" ;;
	focus_key_runtime) printf '%s' "状态" ;;
	focus_key_active) printf '%s' "当前" ;;
	focus_key_general) printf '%s' "概览" ;;
	focus_key_service) printf '%s' "服务" ;;
	focus_key_plane) printf '%s' "入口" ;;
	focus_key_scope) printf '%s' "范围" ;;
	focus_key_kernel) printf '%s' "内核" ;;
	focus_value_tools) printf '%s' "2" ;;
	focus_value_mcp) printf '%s' "PTY" ;;
	focus_value_lifecycle) printf '%s' "重装与卸载" ;;
	focus_value_renewal) printf '%s' "续期" ;;
	focus_value_kernel_scope) printf '%s' "内核" ;;
	focus_value_edge_gateway) printf '%s' "网站入口" ;;
	focus_source_current_theme) printf '%s' "当前主题" ;;
	*) printf '%s' "" ;;
	esac
}

menu_schema_default() {
	local menu_name="${1:-}"
	local section="${2:-}"
	local key="${3:-}"

	case "$section" in
	text)
		case "${menu_name}:${key}" in
		MAIN_MENU:subtitle) menu_vocab_phrase headline_main_subtitle ;;
		MAIN_MENU:repo) menu_vocab_phrase repo_default ;;
		TOOLS_MENU:subtitle) menu_vocab_phrase headline_tools_subtitle ;;
		MCP_MENU:subtitle) menu_vocab_phrase headline_mcp_subtitle ;;
		THEME_MENU:subtitle) menu_vocab_phrase headline_theme_subtitle ;;
		DOCKER_MENU:subtitle | DOCKER_INSTALL_MENU:subtitle | DOCKER_BOOTSTRAP_MENU:subtitle) menu_vocab_phrase headline_docker_subtitle ;;
		CERT_MENU:subtitle | CERT_MAINTENANCE_MENU:subtitle) menu_vocab_phrase headline_cert_subtitle ;;
		WATCHTOWER_MENU:subtitle) menu_vocab_phrase headline_watchtower_subtitle ;;
		BBR_MENU:subtitle) menu_vocab_phrase headline_bbr_subtitle ;;
		BBR_KERNEL_MENU:subtitle) menu_vocab_phrase headline_bbr_kernel_subtitle ;;
		NGINX_MENU:subtitle) menu_vocab_phrase headline_nginx_subtitle ;;
		TOOLS_MENU:hint) menu_vocab_phrase hint_tools ;;
		MCP_MENU:hint) menu_vocab_phrase hint_mcp ;;
		THEME_MENU:hint) menu_vocab_phrase hint_theme ;;
		DOCKER_MENU:hint) menu_vocab_phrase hint_docker ;;
		DOCKER_BOOTSTRAP_MENU:hint) menu_vocab_phrase hint_docker_bootstrap ;;
		DOCKER_INSTALL_MENU:hint) menu_vocab_phrase hint_docker_install ;;
		CERT_MENU:hint) menu_vocab_phrase hint_cert ;;
		CERT_MAINTENANCE_MENU:hint) menu_vocab_phrase hint_cert_maintenance ;;
		WATCHTOWER_MENU:hint) menu_vocab_phrase hint_watchtower ;;
		BBR_MENU:hint) menu_vocab_phrase hint_bbr ;;
		BBR_KERNEL_MENU:hint) menu_vocab_phrase hint_bbr_kernel ;;
		NGINX_MENU:hint) menu_vocab_phrase hint_nginx ;;
		*:subtitle) menu_vocab_phrase headline_generic_subtitle ;;
		*:hint) menu_vocab_phrase hint_generic ;;
		*) printf '%s' "" ;;
		esac
		;;
	meta_label)
		case "$key" in
		version) menu_vocab_phrase label_version ;;
		theme) menu_vocab_phrase label_theme ;;
		update) menu_vocab_phrase label_update ;;
		*) printf '%s' "" ;;
		esac
		;;
	status_label)
		case "${menu_name}:${key}" in
		MAIN_MENU:docker.sh) menu_vocab_phrase label_docker ;;
		MAIN_MENU:nginx.sh) menu_vocab_phrase label_nginx ;;
		MAIN_MENU:tools/Watchtower.sh | TOOLS_MENU:tools/Watchtower.sh) menu_vocab_phrase label_watchtower ;;
		MAIN_MENU:THEME_MENU | MAIN_MENU:set_theme_retro_launcher | MAIN_MENU:set_theme_classic | MAIN_MENU:set_theme_compact | MAIN_MENU:set_theme_minimal)
			menu_vocab_phrase label_current_cn
			;;
		MAIN_MENU:toggle_startup_update_mode) menu_vocab_phrase label_mode_cn ;;
		*) printf '%s' "" ;;
		esac
		;;
	status_marker)
		case "$key" in
		current) menu_vocab_phrase marker_current ;;
		*) printf '%s' "" ;;
		esac
		;;
	group)
		if [ "$key" = "general" ] || [ "$key" = "default" ] || [ -z "$key" ]; then
			menu_vocab_phrase heading_general
			return 0
		fi
		case "${menu_name}:${key}" in
		MAIN_MENU:core) menu_vocab_phrase heading_core_modules ;;
		MAIN_MENU:tools) menu_vocab_phrase heading_tools ;;
		MAIN_MENU:system) menu_vocab_phrase heading_system ;;
		TOOLS_MENU:automation) menu_vocab_phrase heading_automation ;;
		TOOLS_MENU:network) menu_vocab_phrase heading_networking ;;
		MCP_MENU:runtime) menu_vocab_phrase heading_runtime ;;
		MCP_MENU:tooling) menu_vocab_phrase heading_tooling ;;
		THEME_MENU:profiles) menu_vocab_phrase heading_theme_profiles ;;
		*) printf '%s' "$key" ;;
		esac
		;;
	section)
		case "${menu_name}:${key}" in
		DOCKER_MENU:runtime_overview | BBR_MENU:runtime_overview) menu_vocab_phrase heading_runtime_overview ;;
		DOCKER_MENU:action_center | WATCHTOWER_MENU:action_center) menu_vocab_phrase heading_action_center ;;
		DOCKER_MENU:recovery_lifecycle | DOCKER_INSTALL_MENU:recovery_lifecycle | BBR_MENU:recovery_lifecycle | BBR_KERNEL_MENU:recovery_lifecycle)
			menu_vocab_phrase heading_recovery_lifecycle
			;;
		DOCKER_BOOTSTRAP_MENU:bootstrap_overview) menu_vocab_phrase heading_bootstrap_overview ;;
		DOCKER_BOOTSTRAP_MENU:launch_pad) menu_vocab_phrase heading_launch_pad ;;
		CERT_MENU:certificate_overview) menu_vocab_phrase heading_certificate_overview ;;
		CERT_MENU:issue_renew) menu_vocab_phrase heading_issue_renew ;;
		CERT_MENU:policy_control | CERT_MAINTENANCE_MENU:policy_control | BBR_MENU:policy_control)
			menu_vocab_phrase heading_policy_control
			;;
		CERT_MAINTENANCE_MENU:diagnostics) menu_vocab_phrase heading_diagnostics ;;
		WATCHTOWER_MENU:service_overview) menu_vocab_phrase heading_service_overview ;;
		BBR_MENU:profile_control) menu_vocab_phrase heading_profile_control ;;
		NGINX_MENU:http_workloads) menu_vocab_phrase heading_http_workloads ;;
		NGINX_MENU:transport_routing) menu_vocab_phrase heading_transport_routing ;;
		NGINX_MENU:operations_policy) menu_vocab_phrase heading_operations_policy ;;
		*) printf '%s' "$key" ;;
		esac
		;;
	focus_key)
		case "$menu_name" in
		TOOLS_MENU) menu_vocab_phrase focus_key_modules ;;
		MCP_MENU) menu_vocab_phrase focus_key_runtime ;;
		THEME_MENU) menu_vocab_phrase focus_key_active ;;
		DOCKER_MENU | DOCKER_BOOTSTRAP_MENU) menu_vocab_phrase focus_key_runtime ;;
		CERT_MENU | WATCHTOWER_MENU) menu_vocab_phrase focus_key_service ;;
		NGINX_MENU) menu_vocab_phrase focus_key_plane ;;
		DOCKER_INSTALL_MENU | CERT_MAINTENANCE_MENU | BBR_KERNEL_MENU) menu_vocab_phrase focus_key_scope ;;
		BBR_MENU) menu_vocab_phrase focus_key_kernel ;;
		*) menu_vocab_phrase focus_key_general ;;
		esac
		;;
	focus_value)
		case "$menu_name" in
		TOOLS_MENU) menu_vocab_phrase focus_value_tools ;;
		MCP_MENU) menu_vocab_phrase focus_value_mcp ;;
		DOCKER_INSTALL_MENU) menu_vocab_phrase focus_value_lifecycle ;;
		CERT_MAINTENANCE_MENU) menu_vocab_phrase focus_value_renewal ;;
		BBR_KERNEL_MENU) menu_vocab_phrase focus_value_kernel_scope ;;
		NGINX_MENU) menu_vocab_phrase focus_value_edge_gateway ;;
		*) printf '%s' "" ;;
		esac
		;;
	focus_source)
		case "$menu_name" in
		THEME_MENU) menu_vocab_phrase focus_source_current_theme ;;
		*) printf '%s' "" ;;
		esac
		;;
	*) printf '%s' "" ;;
	esac
}

menu_ui_text_field() {
	local menu_name="${1:-}"
	local field="${2:-}"
	local default_value="${3-}"
	local value=""
	if [ "$#" -lt 3 ]; then
		default_value=$(menu_schema_default "$menu_name" "text" "$field")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" --arg field "$field" '.menus[$menu].ui[$field] // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_ui_meta_label() {
	local menu_name="${1:-}"
	local key="${2:-}"
	local default_value="${3-}"
	local value=""
	if [ "$#" -lt 3 ]; then
		default_value=$(menu_schema_default "$menu_name" "meta_label" "$key")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" --arg key "$key" '.menus[$menu].ui.meta_labels[$key] // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_ui_status_label() {
	local menu_name="${1:-}"
	local action="${2:-}"
	local default_value="${3-}"
	local value=""
	if [ "$#" -lt 3 ]; then
		default_value=$(menu_schema_default "$menu_name" "status_label" "$action")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" --arg action "$action" '.menus[$menu].ui.status_labels[$action] // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_ui_status_marker() {
	local menu_name="${1:-}"
	local key="${2:-}"
	local default_value="${3-}"
	local value=""
	if [ "$#" -lt 3 ]; then
		default_value=$(menu_schema_default "$menu_name" "status_marker" "$key")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" --arg key "$key" '.menus[$menu].ui.status_markers[$key] // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_ui_group_label() {
	local menu_name="${1:-}"
	local group="${2:-general}"
	local default_value="${3-}"
	local value=""
	if [ "$#" -lt 3 ]; then
		default_value=$(menu_schema_default "$menu_name" "group" "$group")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" --arg group "$group" '.menus[$menu].ui.groups[$group] // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_ui_section_label() {
	local menu_name="${1:-}"
	local section_key="${2:-}"
	local default_value="${3-}"
	local value=""
	if [ "$#" -lt 3 ]; then
		default_value=$(menu_schema_default "$menu_name" "section" "$section_key")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" --arg section "$section_key" '.menus[$menu].ui.sections[$section] // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_group_heading() {
	local menu_name="${1:-}"
	local group="${2:-general}"
	local default_heading="${3-}"
	if [ "$#" -lt 3 ]; then
		default_heading=$(menu_schema_default "$menu_name" "group" "$group")
	fi
	menu_ui_group_label "$menu_name" "$group" "$default_heading"
}

menu_ui_focus_key() {
	local menu_name="${1:-}"
	local default_value="${2-}"
	local value=""
	if [ "$#" -lt 2 ]; then
		default_value=$(menu_schema_default "$menu_name" "focus_key" "default")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" '.menus[$menu].ui.focus.key // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_ui_focus_value() {
	local menu_name="${1:-}"
	local default_value="${2-}"
	local value=""
	if [ "$#" -lt 2 ]; then
		default_value=$(menu_schema_default "$menu_name" "focus_value" "default")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" '.menus[$menu].ui.focus.value // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_ui_focus_source() {
	local menu_name="${1:-}"
	local default_value="${2-}"
	local value=""
	if [ "$#" -lt 2 ]; then
		default_value=$(menu_schema_default "$menu_name" "focus_source" "default")
	fi
	if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ] && command -v jq >/dev/null 2>&1; then
		value=$(jq -r --arg menu "$menu_name" '.menus[$menu].ui.focus.source // empty' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	printf '%s' "${value:-$default_value}"
}

menu_resolved_focus_value() {
	local menu_name="${1:-}"
	local focus_value=""
	local focus_source=""
	focus_value=$(menu_ui_focus_value "$menu_name")
	focus_source=$(menu_ui_focus_source "$menu_name")
	case "$focus_source" in
	current_theme) ui_theme_label ;;
	*) printf '%s' "$focus_value" ;;
	esac
}

ui_append_schema_panel_header() {
	local target_name="$1"
	local menu_name="$2"
	local focus_value="${3-}"
	local focus_key="${4-}"
	local subtitle=""
	local hint=""

	if [ -z "$focus_key" ]; then
		focus_key=$(menu_ui_focus_key "$menu_name")
	fi
	if [ -z "$focus_value" ]; then
		focus_value=$(menu_resolved_focus_value "$menu_name")
	fi
	subtitle=$(menu_ui_text_field "$menu_name" "subtitle")
	hint=$(menu_ui_text_field "$menu_name" "hint")
	ui_append_panel_header "$target_name" "$subtitle" "$focus_key" "$focus_value" "$hint"
}

ui_append_schema_or_fallback_panel_header() {
	local target_name="$1"
	local menu_name="$2"
	local focus_value="${3-}"
	local focus_key="${4-}"
	local subtitle_default="${5-}"
	local hint_default="${6-}"
	local subtitle=""
	local hint=""

	if [ -z "$focus_key" ]; then
		focus_key=$(menu_ui_focus_key "$menu_name")
	fi
	if [ -z "$focus_value" ]; then
		focus_value=$(menu_resolved_focus_value "$menu_name")
	fi
	subtitle=$(menu_ui_text_field "$menu_name" "subtitle" "$subtitle_default")
	hint=$(menu_ui_text_field "$menu_name" "hint" "$hint_default")
	ui_append_panel_header "$target_name" "$subtitle" "$focus_key" "$focus_value" "$hint"
}

ui_append_schema_page_block() {
	local target_name="$1"
	local menu_name="$2"
	local section_key="$3"
	shift 3
	ui_append_page_block "$target_name" "$(menu_ui_section_label "$menu_name" "$section_key")" "$@"
}

ui_append_schema_or_fallback_page_block() {
	local target_name="$1"
	local menu_name="$2"
	local section_key="$3"
	local heading_default="${4-}"
	shift 4
	ui_append_page_block "$target_name" "$(menu_ui_section_label "$menu_name" "$section_key" "$heading_default")" "$@"
}

ui_define_manual_fallback_helpers() {
	if ! declare -f ui_append_manual_panel_fallback >/dev/null 2>&1; then
		ui_append_manual_panel_fallback() {
			local target_name="$1"
			local subtitle="${2:-}"
			local meta_line="${3:-}"
			local hint="${4:-}"
			if declare -f ui_append_context_lines >/dev/null 2>&1; then
				ui_append_context_lines "$target_name" "$subtitle" "$meta_line" "$hint"
				return 0
			fi
			local -n target_ref="$target_name"
			[ -n "$subtitle" ] && target_ref+=("$subtitle")
			[ -n "$meta_line" ] && target_ref+=("$meta_line")
			[ -n "$hint" ] && target_ref+=("$hint")
		}
	fi

	if ! declare -f ui_append_manual_page_block >/dev/null 2>&1; then
		ui_append_manual_page_block() {
			local target_name="$1"
			local heading="${2:-}"
			shift 2
			if declare -f ui_append_page_block >/dev/null 2>&1; then
				ui_append_page_block "$target_name" "$heading" "$@"
				return 0
			fi
			local -n target_ref="$target_name"
			target_ref+=("")
			if [ -n "$heading" ]; then
				target_ref+=("$heading" "")
			fi
			local item=""
			for item in "$@"; do
				[ -n "$item" ] && target_ref+=("$item")
			done
		}
	fi
}

ui_define_manual_fallback_helpers

ui_define_meta_fallback_helpers() {
	if ! declare -f ui_meta_focus_fallback_line >/dev/null 2>&1; then
		ui_meta_focus_fallback_line() {
			local key="${1:-general}"
			local value="${2:-}"
			local label=""
			local theme_label=""

			if declare -f ui_meta_focus_line >/dev/null 2>&1; then
				ui_meta_focus_line "$key" "$value"
				return 0
			fi

			if declare -f ui_meta_focus_label >/dev/null 2>&1; then
				label=$(ui_meta_focus_label "$key")
			else
				case "$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')" in
				runtime) label="运行状态" ;;
				service) label="服务" ;;
				plane) label="入口" ;;
				scope) label="范围" ;;
				modules) label="模块" ;;
				active) label="当前" ;;
				kernel) label="内核" ;;
				*) label="通用" ;;
				esac
			fi

			if declare -f ui_theme_label >/dev/null 2>&1; then
				theme_label=$(ui_theme_label)
			else
				case "${JB_UI_THEME:-${UI_THEME:-classic}}" in
				retro-launcher) theme_label="启动器风格" ;;
				compact) theme_label="紧凑风格" ;;
				minimal) theme_label="极简风格" ;;
				*) theme_label="经典风格" ;;
				esac
			fi

			if [ -n "$value" ]; then
				printf '主题: %s   |   焦点: %s: %s' "$theme_label" "$label" "$value"
				return 0
			fi
			printf '主题: %s   |   焦点: %s' "$theme_label" "$label"
		}
	fi
}

ui_define_meta_fallback_helpers

ui_meta_focus_label() {
	local key="${1:-general}"
	key=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
	case "$key" in
	runtime) printf '%s' "运行状态" ;;
	service) printf '%s' "服务" ;;
	plane) printf '%s' "入口" ;;
	scope) printf '%s' "范围" ;;
	modules) printf '%s' "模块" ;;
	active) printf '%s' "当前" ;;
	kernel) printf '%s' "内核" ;;
	general) printf '%s' "通用" ;;
	*) printf '%s' "通用" ;;
	esac
}

ui_meta_focus_line() {
	local key="${1:-general}"
	local value="${2:-}"
	if [ -z "$value" ] && [[ "$key" == *:* ]]; then
		value=$(printf '%s' "$key" | cut -d: -f2- | sed 's/^ //')
		key=$(printf '%s' "$key" | cut -d: -f1)
	fi
	local label
	label=$(ui_meta_focus_label "$key")
	if [ -n "$value" ]; then
		printf '主题: %s   |   焦点: %s: %s' "$(ui_theme_label)" "$label" "$value"
		return 0
	fi
	printf '主题: %s   |   焦点: %s' "$(ui_theme_label)" "$label"
}

ui_append_context_lines() {
	local target_name="$1"
	shift
	local -n target_ref="$target_name"
	local line=""
	for line in "$@"; do
		if [ -n "$line" ]; then
			target_ref+=("$line")
		fi
	done
}

ui_append_panel_header() {
	local target_name="$1"
	local subtitle="${2:-}"
	local focus_key="${3:-general}"
	local focus_value="${4:-}"
	local hint="${5:-}"

	ui_append_context_lines "$target_name" "$subtitle" "$(ui_meta_focus_line "$focus_key" "$focus_value")" "$hint"
}

ui_append_main_menu_context() {
	local target_name="$1"
	local subtitle="${2:-}"
	local meta_line="${3:-}"
	local repo_line="${4:-}"

	ui_append_context_lines "$target_name" "$subtitle" "$meta_line" "$repo_line"
}

ui_append_page_block() {
	local target_name="$1"
	local heading="${2:-}"
	shift 2
	local -n target_ref="$target_name"

	target_ref+=("")
	if [ -n "$heading" ]; then
		target_ref+=("$(ui_format_section_heading "$heading")" "")
	fi
	ui_append_context_lines "$target_name" "$@"
}

ui_render_divider() {
	local out="$1"
	local width="${2:-60}"
	local theme
	theme=$(get_ui_theme)
	local line=""
	case "$theme" in
	minimal)
		line=$(ui_repeat_char "$width" "─")
		ui_print_line "$out" "$line"
		;;
	classic)
		line=$(ui_repeat_char "$width" "─")
		ui_print_line "$out" "${GREEN}${line}${NC}"
		;;
	*)
		line=$(ui_repeat_char "$width" "─")
		ui_print_line "$out" "${CYAN}${line}${NC}"
		;;
	esac
}

ui_render_footer() {
	local out="$1"
	local context="${2:-submenu}"
	local theme
	theme=$(get_ui_theme)
	local footer_text
	footer_text=$(ui_menu_footer_text "$context")
	case "$theme" in
	minimal)
		ui_print_line "$out" "$footer_text"
		ui_print_line "$out" "> _"
		;;
	*)
		ui_print_line "$out" "${GRAY}${footer_text}${NC}"
		ui_print_line "$out" "${ORANGE}>${NC} _"
		;;
	esac
}

ui_build_prompt_text() {
	local numeric_range="$1"
	local func_options="${2:-}"
	local context="${3:-submenu}"
	local theme
	theme=$(get_ui_theme)
	if [ "$theme" = "classic" ]; then
		local prompt_text="${ORANGE}>${NC} 选项 "
		if [ -n "$numeric_range" ]; then
			local start="${numeric_range%%-*}"
			local end="${numeric_range##*-}"
			if [ "$start" = "$end" ]; then
				prompt_text+="[${ORANGE}${start}${NC}] "
			else
				prompt_text+="[${ORANGE}${start}${NC}-${end}] "
			fi
		fi
		if [ -n "$func_options" ]; then
			local start="${func_options%%,*}"
			local rest="${func_options#*,}"
			if [ "$start" = "$rest" ]; then
				prompt_text+="[${ORANGE}${start}${NC}] "
			else
				prompt_text+="[${ORANGE}${start}${NC},${rest}] "
			fi
		fi
		prompt_text+="(↩ 返回): "
		printf '%b' "$prompt_text"
		return 0
	fi

	printf '%b\n%b ' "${GRAY}$(ui_menu_footer_text "$context")${NC}" "${ORANGE}>${NC}"
}

ui_render_classic_menu() {
	local out="$1"
	local title="$2"
	shift 2
	local -a lines=("$@")
	local max_content_width=0
	local title_width
	title_width=$(_get_visual_width "$title")
	max_content_width=$title_width
	for line in "${lines[@]}"; do
		local current_line_visual_width
		current_line_visual_width=$(_get_visual_width "$line")
		if [ "$current_line_visual_width" -gt "$max_content_width" ]; then
			max_content_width="$current_line_visual_width"
		fi
	done
	local box_inner_width=$max_content_width
	if [ "$box_inner_width" -lt 40 ]; then box_inner_width=40; fi

	ui_print_blank_line "$out"
	ui_print_line "$out" "${GREEN}╭$(generate_line "$box_inner_width" "─")╮${NC}"
	if [ -n "$title" ]; then
		local padding_total=$((box_inner_width - title_width))
		local padding_left=$((padding_total / 2))
		local padding_right=$((padding_total - padding_left))
		ui_print_line "$out" "${GREEN}│${NC}$(printf '%*s' "$padding_left" '')${BOLD}${title}${NC}$(printf '%*s' "$padding_right" '')${GREEN}│${NC}"
	fi
	ui_print_line "$out" "${GREEN}╰$(generate_line "$box_inner_width" "─")╯${NC}"
	for line in "${lines[@]}"; do
		ui_print_line "$out" "$line"
	done
	local box_total_physical_width=$((box_inner_width + 2))
	ui_print_line "$out" "${GREEN}$(generate_line "$box_total_physical_width" "─")${NC}"
}

ui_render_plain_menu() {
	local out="$1"
	local title="$2"
	shift 2
	local -a lines=("$@")
	local width=60
	local title_width=0
	title_width=$(_get_visual_width "$title")
	if [ "$title_width" -gt "$width" ]; then
		width=$title_width
	fi
	for line in "${lines[@]}"; do
		local current_width=0
		current_width=$(_get_visual_width "$line")
		if [ "$current_width" -gt "$width" ]; then
			width=$current_width
		fi
	done
	if [ "$width" -gt 76 ]; then
		width=76
	fi

	ui_print_blank_line "$out"
	if [ -n "$title" ]; then
		case "$(get_ui_theme)" in
		minimal) ui_print_line "$out" "$title" ;;
		*) ui_print_line "$out" "${BOLD}${title}${NC}" ;;
		esac
	fi
	ui_render_divider "$out" "$width"
	for line in "${lines[@]}"; do
		ui_print_line "$out" "$line"
	done
}

ui_render_main_menu_hero() {
	local title="$1"
	local subtitle="$2"
	local meta_line="$3"
	local repo_line="$4"
	shift 4
	local -a lines=("$@")
	local out
	out=$(ui_output_target)
	local theme
	theme=$(get_ui_theme)

	if [ "$theme" = "classic" ]; then
		ui_render_classic_menu "$out" "$title" "${lines[@]}"
		return 0
	fi

	local cols=0
	if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && [ "${COLUMNS}" -gt 0 ]; then
		cols="${COLUMNS}"
	elif [ -t 1 ]; then
		cols=$(tput cols 2>/dev/null || stty size 2>/dev/null | awk '{print $2}' || echo 0)
	fi
	local hero_mode="full"
	if [ "$theme" = "retro-launcher" ] && ! ui_force_retro_hero_enabled; then
		if [ "$cols" -gt 0 ] && [ "$cols" -lt 44 ]; then
			hero_mode="plain"
		elif [ "$cols" -gt 0 ] && [ "$cols" -lt 74 ]; then
			hero_mode="mobile"
		fi
	fi

	if [ "$theme" = "compact" ]; then
		local -a compact_lines=()
		ui_append_main_menu_context compact_lines "$subtitle" "$meta_line" "$repo_line"
		if [ ${#compact_lines[@]} -gt 0 ] && [ ${#lines[@]} -gt 0 ]; then
			compact_lines+=("")
		fi
		compact_lines+=("${lines[@]}")
		ui_render_plain_menu "$out" "$title" "${compact_lines[@]}"
		return 0
	fi

	if [ "$theme" = "minimal" ]; then
		local -a minimal_lines=()
		ui_append_main_menu_context minimal_lines "$subtitle" "$meta_line" "$repo_line"
		if [ ${#minimal_lines[@]} -gt 0 ] && [ ${#lines[@]} -gt 0 ]; then
			minimal_lines+=("")
		fi
		minimal_lines+=("${lines[@]}")
		ui_render_plain_menu "$out" "$title" "${minimal_lines[@]}"
		return 0
	fi

	if [ "$hero_mode" = "plain" ]; then
		local -a plain_lines=()
		ui_append_main_menu_context plain_lines "$subtitle" "$meta_line" "$repo_line"
		if [ ${#plain_lines[@]} -gt 0 ] && [ ${#lines[@]} -gt 0 ]; then
			plain_lines+=("")
		fi
		plain_lines+=("${lines[@]}")
		ui_render_plain_menu "$out" "$title" "${plain_lines[@]}"
		return 0
	fi

	if [ "$hero_mode" = "mobile" ]; then
		ui_print_blank_line "$out"
		ui_print_line "$out" "${GREEN}██╗   ██╗██╗  ██╗███╗   ███╗${NC}"
		ui_print_line "$out" "${GREEN}██║   ██║██║ ██╔╝████╗ ████║${NC}"
		ui_print_line "$out" "${GREEN}██║   ██║█████╔╝ ██╔████╔██║${NC}"
		ui_print_line "$out" "${GREEN}╚██╗ ██╔╝██╔═██╗ ██║╚██╔╝██║${NC}"
		ui_print_line "$out" "${GREEN} ╚████╔╝ ██║  ██╗██║ ╚═╝ ██║${NC}"
		ui_print_line "$out" "${GREEN}  ╚═══╝  ╚═╝  ╚═╝╚═╝     ╚═╝${NC}"
		ui_print_blank_line "$out"
		ui_print_line "$out" "${BOLD}${title}${NC}"
		ui_print_line "$out" "$subtitle"
		ui_render_divider "$out" 52
		ui_print_line "$out" "${GRAY}${meta_line}${NC}"
		ui_print_line "$out" "${GRAY}${repo_line}${NC}"
		for line in "${lines[@]}"; do
			ui_print_line "$out" "$line"
		done
		return 0
	fi

	ui_print_blank_line "$out"
	ui_print_line "$out" "+--------------------------------------------------------------------------+"
	ui_print_line "$out" "|                                                                          |"
	ui_print_line "$out" "|  ██╗   ██╗██╗  ██╗███╗   ███╗                                            |"
	ui_print_line "$out" "|  ██║   ██║██║ ██╔╝████╗ ████║                                            |"
	ui_print_line "$out" "|  ██║   ██║█████╔╝ ██╔████╔██║                                            |"
	ui_print_line "$out" "|  ╚██╗ ██╔╝██╔═██╗ ██║╚██╔╝██║                                            |"
	ui_print_line "$out" "|   ╚████╔╝ ██║  ██╗██║ ╚═╝ ██║                                            |"
	ui_print_line "$out" "|    ╚═══╝  ╚═╝  ╚═╝╚═╝     ╚═╝                                            |"
	ui_print_line "$out" "|                                                                          |"
	ui_print_line "$out" "|  ${BOLD}${title}${NC}"
	ui_print_line "$out" "|  ${subtitle}"
	ui_print_line "$out" "|                                                                          |"
	ui_print_line "$out" "+--------------------------------------------------------------------------+"
	ui_print_blank_line "$out"
	local -a hero_context_lines=()
	ui_append_main_menu_context hero_context_lines "" "$meta_line" "$repo_line"
	local context_line=""
	for context_line in "${hero_context_lines[@]}"; do
		ui_print_line "$out" "${GRAY}${context_line}${NC}"
	done
	for line in "${lines[@]}"; do
		ui_print_line "$out" "$line"
	done
}

# --- 清屏策略 ---
# shellcheck disable=SC2034
declare -A JB_SMART_CLEAR_SEEN=()

normalize_clear_mode() {
	local mode="${JB_CLEAR_MODE:-}"
	if [ -z "$mode" ]; then
		if [ "${JB_ENABLE_AUTO_CLEAR:-false}" = "true" ]; then
			mode="full"
		else
			mode="off"
		fi
	fi
	case "${mode,,}" in
	off | false | 0) printf '%s' "off" ;;
	full | true | 1) printf '%s' "full" ;;
	smart) printf '%s' "smart" ;;
	*) printf '%s' "off" ;;
	esac
	return 0
}

should_clear_screen() {
	local menu_key="${1:-__default_menu__}"
	local clear_mode
	if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
		return 1
	fi
	clear_mode="$(normalize_clear_mode)"
	case "$clear_mode" in
	off) return 1 ;;
	full) return 0 ;;
	smart)
		if [ -n "${JB_SMART_CLEAR_SEEN[$menu_key]+x}" ]; then
			return 1
		fi
		JB_SMART_CLEAR_SEEN["$menu_key"]=1
		return 0
		;;
	*) return 1 ;;
	esac
}

# --- 配置加载 (优化版) ---
_get_json_value_fallback() {
	local file="$1"
	local key="$2"
	local default_val="$3"
	local result
	result=$(sed -n 's/.*"'"$key"'": *"\([^"]*\)".*/\1/p' "$file")
	echo "${result:-$default_val}"
}

load_config() {
	local config_path="${1:-${CONFIG_PATH:-${DEFAULT_CONFIG_PATH}}}"
	BASE_URL="${BASE_URL:-$DEFAULT_BASE_URL}"
	INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
	BIN_DIR="${BIN_DIR:-$DEFAULT_BIN_DIR}"
	LOCK_FILE="${LOCK_FILE:-$DEFAULT_LOCK_FILE}"
	JB_TIMEZONE="${JB_TIMEZONE:-$DEFAULT_TIMEZONE}"
	CONFIG_PATH="$config_path"
	JB_LOG_WITH_TIMESTAMP="${JB_LOG_WITH_TIMESTAMP:-$DEFAULT_LOG_WITH_TIMESTAMP}"
	if [ -n "${JB_LOG_LEVEL_OVERRIDE:-}" ]; then
		case "${JB_LOG_LEVEL_OVERRIDE}" in
		ERROR | WARN | INFO | DEBUG)
			LOG_LEVEL="${JB_LOG_LEVEL_OVERRIDE}"
			log_info "应用临时日志级别覆盖: ${LOG_LEVEL}"
			;;
		esac
	fi
	JB_ENABLE_AUTO_UPDATE="${JB_ENABLE_AUTO_UPDATE:-$DEFAULT_ENABLE_AUTO_UPDATE}"
	JB_NONINTERACTIVE="${JB_NONINTERACTIVE:-$DEFAULT_NONINTERACTIVE}"
	JB_TTY_PATH="${JB_TTY_PATH:-$DEFAULT_TTY_PATH}"
	# shellcheck disable=SC2034
	JB_CLEAR_MODE="off"
	LOG_FILE="${LOG_FILE:-${DEFAULT_LOG_FILE}}"
	LOG_LEVEL="${LOG_LEVEL:-${DEFAULT_LOG_LEVEL}}"

	sanitize_noninteractive_flag

	if [ ! -f "$config_path" ]; then
		log_warn "配置文件 $config_path 未找到，使用默认配置。"
		return 0
	fi

	if command -v jq >/dev/null 2>&1; then
		BASE_URL=$(jq -r '.base_url // empty' "$config_path" 2>/dev/null || echo "$BASE_URL")
		INSTALL_DIR=$(jq -r '.install_dir // empty' "$config_path" 2>/dev/null || echo "$INSTALL_DIR")
		BIN_DIR=$(jq -r '.bin_dir // empty' "$config_path" 2>/dev/null || echo "$BIN_DIR")
		LOCK_FILE=$(jq -r '.lock_file // empty' "$config_path" 2>/dev/null || echo "$LOCK_FILE")
		JB_TIMEZONE=$(jq -r '.timezone // empty' "$config_path" 2>/dev/null || echo "$JB_TIMEZONE")
		JB_LOG_WITH_TIMESTAMP=$(jq -r '.log_with_timestamp // false' "$config_path" 2>/dev/null || echo "$JB_LOG_WITH_TIMESTAMP")
		JB_ENABLE_AUTO_UPDATE=$(jq -r '.enable_auto_update // "true"' "$config_path" 2>/dev/null || echo "$JB_ENABLE_AUTO_UPDATE")
		JB_NONINTERACTIVE=$(jq -r '.noninteractive // "false"' "$config_path" 2>/dev/null || echo "$JB_NONINTERACTIVE")
		UI_THEME=$(jq -r --arg def "$DEFAULT_UI_THEME" '.ui.theme // $def' "$config_path" 2>/dev/null || echo "$DEFAULT_UI_THEME")
		UI_FORCE_RETRO_HERO=$(jq -r --arg def "$DEFAULT_FORCE_RETRO_HERO" '.ui.force_retro_hero // $def' "$config_path" 2>/dev/null || echo "$DEFAULT_FORCE_RETRO_HERO")
	else
		log_warn "未检测到 jq，使用轻量文本解析。"
		BASE_URL=$(_get_json_value_fallback "$config_path" "base_url" "$BASE_URL")
		INSTALL_DIR=$(_get_json_value_fallback "$config_path" "install_dir" "$INSTALL_DIR")
		BIN_DIR=$(_get_json_value_fallback "$config_path" "bin_dir" "$BIN_DIR")
		LOCK_FILE=$(_get_json_value_fallback "$config_path" "lock_file" "$LOCK_FILE")
		JB_TIMEZONE=$(_get_json_value_fallback "$config_path" "timezone" "$JB_TIMEZONE")
		JB_LOG_WITH_TIMESTAMP=$(_get_json_value_fallback "$config_path" "log_with_timestamp" "$JB_LOG_WITH_TIMESTAMP")
		JB_ENABLE_AUTO_UPDATE=$(_get_json_value_fallback "$config_path" "enable_auto_update" "$JB_ENABLE_AUTO_UPDATE")
		JB_NONINTERACTIVE=$(_get_json_value_fallback "$config_path" "noninteractive" "$JB_NONINTERACTIVE")
		UI_THEME=$(_get_json_value_fallback "$config_path" "theme" "$DEFAULT_UI_THEME")
		UI_FORCE_RETRO_HERO="$DEFAULT_FORCE_RETRO_HERO"
	fi

	if ! ui_theme_exists "${UI_THEME:-}"; then
		UI_THEME="$DEFAULT_UI_THEME"
	fi
	if [ -z "${JB_UI_THEME:-}" ]; then
		JB_UI_THEME="$UI_THEME"
	fi
	JB_FORCE_RETRO_HERO="${JB_FORCE_RETRO_HERO:-$UI_FORCE_RETRO_HERO}"

	# shellcheck disable=SC2034
	JB_CLEAR_MODE="$(normalize_clear_mode)"
}

# --- UI 渲染 & 字符串处理 (性能优化版) ---
generate_line() {
	local len=${1:-40}
	local char=${2:-"─"}
	if [ "$len" -le 0 ]; then
		echo ""
		return
	fi

	# [优化点] 使用 Bash 原生 printf 和字符串替换，避免 fork sed 子进程
	# 旧方法: printf "%${len}s" "" | sed "s/ /$char/g"  (生成速度快，但多一个进程)
	# 新方法: Bash 参数扩展替换 (纯内存操作)
	local spaces
	printf -v spaces "%${len}s" ""
	echo "${spaces// /$char}"
}

_get_visual_width() {
	local text="$1"
	local plain_text
	plain_text=$(printf '%b' "$text" | sed 's/\x1b\[[0-9;]*m//g')
	if [ -z "$plain_text" ]; then
		echo 0
		return
	fi
	if command -v python3 >/dev/null 2>&1; then
		python3 -c "import unicodedata,sys; s=sys.stdin.read(); print(sum(2 if unicodedata.east_asian_width(c) in ('W','F','A') else 1 for c in s.strip()))" <<<"$plain_text" 2>/dev/null || echo "${#plain_text}"
	elif command -v wc >/dev/null 2>&1 && wc --help 2>&1 | grep -q -- "-m"; then
		printf '%s' "$plain_text" | wc -m
	else
		echo "${#plain_text}"
	fi
}

_render_menu() {
	local title="$1"
	shift
	local -a lines=("$@")
	local out
	out=$(ui_output_target)
	case "$(get_ui_theme)" in
	classic)
		ui_render_classic_menu "$out" "$title" "${lines[@]}"
		;;
	minimal)
		ui_render_plain_menu "$out" "$title" "${lines[@]}"
		;;
	*)
		ui_render_plain_menu "$out" "$title" "${lines[@]}"
		;;
	esac
}

_on_error() {
	local exit_code="$1"
	local line_no="$2"
	log_err "运行出错: exit_code=${exit_code}, line=${line_no}"
	return "$exit_code"
}

_cleanup() {
	:
}

main() {
	trap '_on_error "$?" "$LINENO"' ERR
	trap _cleanup EXIT

	log_info "启动: utils.sh"
	log_info "环境: LOG_LEVEL=${LOG_LEVEL:-${DEFAULT_LOG_LEVEL}}, LOG_FILE=${LOG_FILE:-${DEFAULT_LOG_FILE}}"
	return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
