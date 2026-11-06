#!/usr/bin/env bash

if ! declare -f ui_define_manual_fallback_helpers >/dev/null 2>&1; then
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
fi

if ! declare -f ui_define_meta_fallback_helpers >/dev/null 2>&1; then
	ui_define_meta_fallback_helpers() {
		if ! declare -f ui_meta_focus_fallback_line >/dev/null 2>&1; then
			ui_meta_focus_fallback_line() {
				local key="${1:-general}"
				local value="${2:-}"
				local label="通用"
				case "$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')" in
				runtime) label="运行状态" ;;
				service) label="服务" ;;
				plane) label="入口" ;;
				scope) label="范围" ;;
				modules) label="模块" ;;
				active) label="当前" ;;
				kernel) label="内核" ;;
				esac
				local theme_label="经典风格"
				case "${JB_UI_THEME:-${UI_THEME:-classic}}" in
				retro-launcher) theme_label="启动器风格" ;;
				compact) theme_label="紧凑风格" ;;
				minimal) theme_label="极简风格" ;;
				esac
				if [ -n "$value" ]; then
					printf '主题: %s   |   焦点: %s: %s' "$theme_label" "$label" "$value"
				else
					printf '主题: %s   |   焦点: %s' "$theme_label" "$label"
				fi
			}
		fi
	}
fi

ui_define_manual_fallback_helpers
ui_define_meta_fallback_helpers

check_and_auto_renew_certs() {
	_generate_op_id
	if ! acquire_cert_lock; then return 1; fi
	if ! preflight_hard_gate "cron_renew"; then
		return "${ERR_CFG_VALIDATE:-20}"
	fi
	log_message INFO "正在执行 Cron 守护检测并批量续期..."
	local success=0 fail=0
	local reload_needed="false"
	_renew_fail_cleanup
	local IFS=$'\1'
	while IFS=$'\1' read -r domain cert_file method; do
		[[ -z "$domain" ]] && continue
		printf '%b' "检查: $domain ... "
		if [ "$method" == "reuse" ]; then
			printf '%b' "跳过(跟随主域)\n"
			continue
		fi
		local should_reload="false"
		if [ ! -f "$cert_file" ] || ! openssl x509 -checkend $((RENEW_THRESHOLD_DAYS * 86400)) -noout -in "$cert_file"; then
			printf '%b' "${BRIGHT_RED}触发续期...${NC}\n"
			local project_json
			project_json=$(_get_project_json "$domain")
			if [[ -n "$project_json" ]]; then
				if _issue_and_install_certificate "$project_json"; then
					success=$((success + 1))
					_renew_fail_reset "$domain"
					_send_tg_notify "success" "$domain" "证书已成功安装。" ""
					should_reload="true"
				else
					fail=$((fail + 1))
					local fcount
					fcount=$(_renew_fail_incr "$domain")
					if [ "$fcount" -ge "$RENEW_FAIL_THRESHOLD" ]; then
						_send_tg_notify "fail" "$domain" "自动续签失败(${fcount}次)。" ""
					else
						log_message WARN "续签失败次数未达阈值(${fcount}/${RENEW_FAIL_THRESHOLD})，暂不通知。"
					fi
				fi
			else
				log_message ERROR "无法读取 $domain 的配置元数据"
				fail=$((fail + 1))
			fi
		else printf '%b' "${GREEN}有效期充足${NC}\n"; fi
		if [ "$should_reload" = "true" ]; then reload_needed="true"; fi
	done < <(jq -r '.[] | "\(.domain)\1\(.cert_file)\1\(.acme_validation_method)' "$PROJECTS_METADATA_FILE" 2>/dev/null)
	unset IFS
	# shellcheck disable=SC2034
	NGINX_RELOAD_NEEDED="${reload_needed}"
	if ! control_nginx_reload_if_needed; then
		_tx_emit_marker "RECONCILE_DRIFT" "reload_failed during cron_renew" "ERROR"
		return 1
	fi

	log_message INFO "批量任务结束: $success 成功, $fail 失败。"
	if [ "$fail" -gt 0 ]; then
		_tx_emit_marker "RECONCILE_DRIFT" "renew_failures=${fail}" "ERROR"
		return 1
	fi
	_tx_emit_marker "RECONCILE_OK" "renew_success=${success}"
	return 0
}

configure_nginx_projects() {
	_generate_op_id
	local mode="${1:-standard}"
	local json
	_ensure_menu_interactive
	if [ "${JB_NONINTERACTIVE:-false}" = "true" ] || [ "$IS_INTERACTIVE_MODE" != "true" ]; then
		log_message ERROR "非交互模式无法配置新项目"
		return 1
	fi
	printf '%b' "\n${CYAN}开始配置新项目...${NC}\n"
	if ! json=$(_gather_project_details "{}" "false" "$mode"); then
		log_message WARN "用户取消配置。"
		return
	fi

	_issue_and_install_certificate "$json"
	local domain method
	IFS=$'\t' read -r domain method < <(jq -r '[.domain, (.acme_validation_method // "")] | @tsv' <<<"$json")
	local old_json=""
	old_json=$(_get_project_json "$domain")
	local cert="$SSL_CERTS_BASE_DIR/$domain.cer"
	if [ -f "$cert" ] || [ "$method" = "reuse" ]; then
		snapshot_project_json "$domain" "$json"
		if _apply_project_transaction "$domain" "$json" "$old_json" "$mode"; then
			log_message SUCCESS "配置已保存。"
			if [ -n "$LAST_CERT_ELAPSED" ]; then printf '%b' "\n申请耗时: ${LAST_CERT_ELAPSED}\n"; fi
			if [ -n "$LAST_CERT_CERT" ] && [ -n "$LAST_CERT_KEY" ]; then
				printf '%b' "证书路径: ${LAST_CERT_CERT}\n"
				printf '%b' "私钥路径: ${LAST_CERT_KEY}\n"
			fi
			if [ "$mode" != "cert_only" ]; then
				printf '%b' "\n网站已上线: https://${domain}\n"
			fi
		else
			log_message WARN "配置失败，已执行回滚。"
		fi
	else log_message ERROR "证书申请失败,未保存。"; fi
}

# --- 主菜单版式辅助（方案 D） -------------------------------------------------
# 编号纯文字 + 标签定宽 + 说明；状态区为「键值 + 缩进明细 + 修复出口」。
# 对齐按显示列计算（中文占 2 列），不依赖字面空格数量，窄屏也不产生孤字折行。

# 终端列数（取不到时按 80，下限 24）
_nginx_term_cols() {
	local cols="${COLUMNS:-0}"
	if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
		cols=$(tput cols 2>/dev/null || printf '%s' "$cols")
	fi
	case "$cols" in
	'' | *[!0-9]*) cols=0 ;;
	esac
	[ "$cols" -le 0 ] && cols=80
	[ "$cols" -lt 24 ] && cols=24
	printf '%s\n' "$cols"
}

# 补齐到指定显示列数；已超宽则原样返回
_nginx_pad_visual() {
	local text="$1" target="$2" width
	width=$(_get_visual_width "$text")
	if [ "$width" -ge "$target" ]; then
		printf '%s' "$text"
		return 0
	fi
	printf '%s%*s' "$text" $((target - width)) ''
}

# 按显示列粗截断（中文按 2 列估算，保证不超宽），超出补省略号
_nginx_trim_visual() {
	local text="$1" limit="$2" width
	width=$(_get_visual_width "$text")
	if [ "$width" -le "$limit" ]; then
		printf '%s' "$text"
		return 0
	fi
	if command -v python3 >/dev/null 2>&1; then
		printf '%s' "$text" | python3 -c '
import sys, unicodedata
limit = int(sys.argv[1])
s = sys.stdin.read().strip()
out = ""
width = 0
for ch in s:
    cw = 2 if unicodedata.east_asian_width(ch) in ("W", "F", "A") else 1
    if width + cw > limit - 1:
        break
    out += ch
    width += cw
sys.stdout.write(out + "…")
' "$limit" 2>/dev/null && return 0
	fi
	# 取不到 python 时按字符数保守截断（中文按 2 列估算）
	printf '%s…' "${text:0:$((limit / 2))}"
}

# 一行菜单项：编号右对齐 2 列 + 标签 16 列 + 说明
_nginx_menu_row() {
	local num="$1" label="$2" desc="${3:-}" color="${4:-}" limit
	# 编号 2 列 + 分隔 2 列 + 标签 16 列 + 分隔 1 列 = 21 列，其余留给说明
	limit=$(($(_nginx_term_cols) - 21))
	[ "$limit" -lt 8 ] && limit=8
	desc=$(_nginx_trim_visual "$desc" "$limit")
	# 传了颜色就整行上色（危险项），说明文字不再用灰色，避免与底色冲突
	if [ -n "$color" ]; then
		printf '%s%s  %s %s%b' "$color" "$(printf '%2s' "$num")" "$(_nginx_pad_visual "$label" 16)" "$desc" "$NC"
	else
		printf '%s  %s %s' "$(printf '%2s' "$num")" "$(_nginx_pad_visual "$label" 16)" "${GRAY}${desc}${NC}"
	fi
}

_nginx_status_color() {
	case "$1" in
	正常) printf '%s' "$GREEN" ;;
	需关注) printf '%s' "$YELLOW" ;;
	*) printf '%s' "$BRIGHT_RED" ;;
	esac
}

_nginx_status_row() {
	local label="$1" value="$2" color
	color=$(_nginx_status_color "$value")
	printf '%s%s%s%s' "$(_nginx_pad_visual "$label" 12)" "$color" "$value" "$NC"
}

_nginx_status_detail() {
	local limit
	limit=$(($(_nginx_term_cols) - 14))
	[ "$limit" -lt 20 ] && limit=20
	[ "$limit" -gt 46 ] && limit=46
	printf '            %s%s%s' "$GRAY" "$(_nginx_trim_visual "$1" "$limit")" "$NC"
}

_nginx_status_hint() {
	printf '            %s→ %s%s' "$GRAY" "$1" "$NC"
}

# 把「；」分隔的原因拆成明细行，超过 limit 条折成计数
_nginx_status_details() {
	local reason="$1" limit="${2:-3}" item="" shown=0 total=0
	local -a raw=() items=()
	IFS='；' read -r -a raw <<<"$reason"
	# 先剔除空项，否则「还有 N 项」的计数会把结尾多余的分号也算进去
	for item in "${raw[@]}"; do
		if [ -n "$item" ]; then
			items+=("$item")
		fi
	done
	total=${#items[@]}
	for item in "${items[@]}"; do
		if [ "$shown" -ge "$limit" ]; then
			printf '%s\n' "还有 $((total - limit)) 项"
			return 0
		fi
		printf '%s\n' "$item"
		shown=$((shown + 1))
	done
}

# 配置检查的修复出口：只有临时目录权限类可用菜单 13
_nginx_config_health_hint() {
	case "$1" in
	*目录* | *权限* | *写入*) printf '%s' "菜单 13 共享组修复" ;;
	*) printf '' ;;
	esac
}

# 证书状态的修复出口：非正常时都给续期入口
_nginx_cert_health_hint() {
	[ "$1" = "正常" ] && return 0
	printf '%s' "菜单 6 批量续期"
}

# 状态区行：键值 + 缩进明细 + 修复出口
_nginx_status_lines() {
	local config_status config_reason cert_status cert_reason detail="" hint=""
	IFS=$'\t' read -r config_status config_reason < <(_nginx_config_health_status)
	IFS=$'\t' read -r cert_status cert_reason < <(_nginx_cert_health_status)
	_nginx_status_row "配置检查" "$config_status"
	printf '\n'
	while IFS= read -r detail; do
		if [ -n "$detail" ]; then
			_nginx_status_detail "$detail"
			printf '\n'
		fi
	done < <(_nginx_status_details "$config_reason" 3)
	hint=$(_nginx_config_health_hint "$config_reason")
	if [ -n "$hint" ]; then
		_nginx_status_hint "$hint"
		printf '\n'
	fi
	_nginx_status_row "证书状态" "$cert_status"
	printf '\n'
	while IFS= read -r detail; do
		if [ -n "$detail" ]; then
			_nginx_status_detail "$detail"
			printf '\n'
		fi
	done < <(_nginx_status_details "$cert_reason" 3)
	hint=$(_nginx_cert_health_hint "$cert_status")
	if [ -n "$hint" ]; then
		_nginx_status_hint "$hint"
		printf '\n'
	fi
}

# 常用操作分组
_nginx_menu_common_rows() {
	_nginx_menu_row 1 "配置新网站" "新建反向代理网站"
	printf '\n'
	_nginx_menu_row 2 "管理网站" "查看、修改或删除"
	printf '\n'
	_nginx_menu_row 3 "仅申请证书" "只管理证书"
	printf '\n'
	_nginx_menu_row 4 "配置 TCP 转发" "新建反代或负载均衡"
	printf '\n'
	_nginx_menu_row 5 "管理 TCP 转发" "查看或删除 TCP 项目"
	printf '\n'
}

# 诊断与策略分组
_nginx_menu_policy_rows() {
	_nginx_menu_row 6 "批量续期" "检查并续期现有证书"
	printf '\n'
	_nginx_menu_row 7 "查看日志" "nginx 与 acme 日志"
	printf '\n'
	_nginx_menu_row 8 "Cloudflare 防御" "管理状态与 IP 库"
	printf '\n'
	_nginx_menu_row 9 "备份与恢复" "备份、还原与重建"
	printf '\n'
	_nginx_menu_row 10 "Telegram 通知" "机器人通知"
	printf '\n'
	_nginx_menu_row 11 "配置模板中心" "Block 与 Site 模板"
	printf '\n'
	_nginx_menu_row 12 "升级 Nginx" "从官方源升级"
	printf '\n'
	_nginx_menu_row 13 "修复目录冲突" "共享组修复权限"
	printf '\n'
}

main_menu() {
	_generate_op_id
	_ensure_menu_interactive
	while true; do
		_draw_dashboard
		JB_MENU_CONTEXT="submenu"
		local -a status_lines=() menu_common=() menu_policy=()
		mapfile -t status_lines < <(_nginx_status_lines)
		mapfile -t menu_common < <(_nginx_menu_common_rows)
		mapfile -t menu_policy < <(_nginx_menu_policy_rows)

		if declare -f get_ui_theme >/dev/null 2>&1 && [ "$(get_ui_theme)" != "classic" ]; then
			local -a menu_lines=()
			if declare -f ui_append_schema_or_fallback_page_block >/dev/null 2>&1; then
				ui_append_schema_or_fallback_page_block menu_lines "NGINX_MENU" "runtime_overview" "当前状态" \
					"${status_lines[@]}"
				ui_append_schema_or_fallback_page_block menu_lines "NGINX_MENU" "transport_routing" "常用操作" \
					"${menu_common[@]}"
				ui_append_schema_or_fallback_page_block menu_lines "NGINX_MENU" "operations_policy" "诊断与策略" \
					"${menu_policy[@]}"
			else
				ui_append_manual_page_block menu_lines "当前状态" "${status_lines[@]}"
				ui_append_manual_page_block menu_lines "常用操作" "${menu_common[@]}"
				ui_append_manual_page_block menu_lines "诊断与策略" "${menu_policy[@]}"
			fi
			_render_menu "Nginx 管理" "${menu_lines[@]}"
		else
			local row=""
			printf '%b' "${CYAN}当前状态${NC}\n"
			for row in "${status_lines[@]}"; do
				printf ' %s\n' "$row"
			done
			printf '%b' "\n${CYAN}常用操作${NC}\n"
			for row in "${menu_common[@]}"; do
				printf ' %s\n' "$row"
			done
			printf '%b' "\n${CYAN}诊断与策略${NC}\n"
			for row in "${menu_policy[@]}"; do
				printf ' %s\n' "$row"
			done
			printf '%b' "\n"
		fi
		local c
		if ! c=$(prompt_menu_choice "1-13" "true"); then
			exit 10
		fi
		case "$c" in
		1)
			configure_nginx_projects
			press_enter_to_continue
			;;
		2) manage_configs ;;
		3)
			configure_nginx_projects "cert_only"
			press_enter_to_continue
			;;
		4)
			configure_tcp_proxy
			press_enter_to_continue
			;;
		5) manage_tcp_configs ;;
		6) if confirm_or_cancel "确认检查所有项目?"; then
			check_and_auto_renew_certs
			press_enter_to_continue
		fi ;;
		7)
			_render_menu "查看日志" "1. Nginx 全局访问/错误日志" "2. acme.sh 证书运行日志"
			local log_c
			if log_c=$(prompt_menu_choice "1-2" "true"); then
				if [ "$log_c" = "1" ]; then
					_view_nginx_global_log
				else
					_view_acme_log
				fi
				press_enter_to_continue
			fi
			;;
		8) _manage_cloudflare_defense ;;
		9) _handle_backup_restore ;;
		10)
			setup_tg_notifier
			press_enter_to_continue
			;;
		11) _manage_nginx_template_center ;;
		12)
			upgrade_nginx_official_repo
			press_enter_to_continue
			;;
		13)
			_fix_nginx_temp_path_conflicts
			press_enter_to_continue
			;;
		"") exit 10 ;;
		*) log_message ERROR "无效选择" ;;
		esac
	done
}

_ensure_menu_interactive() {
	if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
		return 0
	fi
	if [ "${IS_INTERACTIVE_MODE}" = "true" ]; then
		return 0
	fi
	if [ -t 0 ] || _tty_available; then
		IS_INTERACTIVE_MODE="true"
		log_message WARN "检测到交互终端，已恢复交互模式"
	fi
}
