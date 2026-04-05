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

main_menu() {
	_generate_op_id
	_ensure_menu_interactive
	while true; do
		_draw_dashboard
		JB_MENU_CONTEXT="submenu"
		local config_status config_reason cert_status cert_reason
		IFS=$'\t' read -r config_status config_reason < <(_nginx_config_health_status)
		IFS=$'\t' read -r cert_status cert_reason < <(_nginx_cert_health_status)
		local config_line="- 配置检查    ${config_status}"
		local cert_line="- 证书状态    ${cert_status}"
		[ -n "$config_reason" ] && config_line+="，${config_reason}"
		[ -n "$cert_reason" ] && cert_line+="，${cert_reason}"
		if declare -f get_ui_theme >/dev/null 2>&1 && [ "$(get_ui_theme)" != "classic" ]; then
			local -a menu_lines=()
			if declare -f ui_append_schema_or_fallback_page_block >/dev/null 2>&1; then
				ui_append_schema_or_fallback_page_block menu_lines "NGINX_MENU" "runtime_overview" "当前状态" \
					"${config_line}" \
					"${cert_line}"
				ui_append_schema_or_fallback_page_block menu_lines "NGINX_MENU" "transport_routing" "常用操作" \
					"● 1. 🌐 配置新网站        新建反向代理网站" \
					"○ 2. 🗂️ 管理网站          查看、修改或删除网站" \
					"○ 3. 📜 仅申请证书        只管理证书，不配置代理" \
					"○ 4. 🔀 配置 TCP 转发     新建 TCP 反代或负载均衡" \
					"○ 5. 🧩 管理 TCP 转发     查看、修改或删除 TCP 项目"
				ui_append_schema_or_fallback_page_block menu_lines "NGINX_MENU" "operations_policy" "诊断与策略" \
					"○ 6. 🔁 批量续期          检查并续期现有证书" \
					"○ 7. 📄 查看日志          查看 Nginx 和 acme 日志" \
					"○ 8. 🛡️ Cloudflare 防御   管理防御状态和 IP 库" \
					"○ 9. 💾 备份与恢复        备份、还原和配置重建" \
					"○ 10. 🤖 Telegram 通知    配置机器人通知" \
					"○ 11. 🧱 配置模板中心     管理 Block 和 Site 模板" \
					"! 12. ⬆️ 升级 Nginx       从官方源升级"
			else
				ui_append_manual_page_block menu_lines "当前状态" \
					"${config_line}" \
					"${cert_line}"
				ui_append_manual_page_block menu_lines "常用操作" \
					"● 1. 🌐 配置新网站        新建反向代理网站" \
					"○ 2. 🗂️ 管理网站          查看、修改或删除网站" \
					"○ 3. 📜 仅申请证书        只管理证书，不配置代理" \
					"○ 4. 🔀 配置 TCP 转发     新建 TCP 反代或负载均衡" \
					"○ 5. 🧩 管理 TCP 转发     查看、修改或删除 TCP 项目"
				ui_append_manual_page_block menu_lines "诊断与策略" \
					"○ 6. 🔁 批量续期          检查并续期现有证书" \
					"○ 7. 📄 查看日志          查看 Nginx 和 acme 日志" \
					"○ 8. 🛡️ Cloudflare 防御   管理防御状态和 IP 库" \
					"○ 9. 💾 备份与恢复        备份、还原和配置重建" \
					"○ 10. 🤖 Telegram 通知    配置机器人通知" \
					"○ 11. 🧱 配置模板中心     管理 Block 和 Site 模板" \
					"! 12. ⬆️ 升级 Nginx       从官方源升级"
			fi
			_render_menu "Nginx 管理" "${menu_lines[@]}"
		else
			printf '%b' "${CYAN}当前状态${NC}\n"
			printf '%b' " ${config_line}\n"
			printf '%b' " ${cert_line}\n"
			printf '%b' "\n"
			printf '%b' "${CYAN}常用操作${NC}\n"
			printf '%b' " ● 1. 配置新网站\n"
			printf '%b' " ○ 2. 管理网站\n"
			printf '%b' " ○ 3. 仅申请证书\n"
			printf '%b' " ○ 4. 配置 TCP 转发\n"
			printf '%b' " ○ 5. 管理 TCP 转发\n"
			printf '%b' "\n"
			printf '%b' "${CYAN}诊断与策略${NC}\n"
			printf '%b' " ○ 6. 批量续期\n"
			printf '%b' " ○ 7. 查看日志\n"
			printf '%b' " ○ 8. Cloudflare 防御\n"
			printf '%b' " ○ 9. 备份与恢复\n"
			printf '%b' " ○ 10. Telegram 通知\n"
			printf '%b' " ○ 11. 配置模板中心\n"
			printf '%b' " ! 12. 升级 Nginx\n"
			printf '%b' "\n"
		fi
		local c
		if ! c=$(prompt_menu_choice "1-12" "true"); then
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
