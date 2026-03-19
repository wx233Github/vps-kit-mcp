#!/usr/bin/env bash
# =============================================================
# 🚀 Watchtower 自动更新管理器 (v6.5.7-精简交互版)
# =============================================================
# 作者：系统运维组
# 描述：Docker 容器自动更新管理 (Watchtower) 封装脚本
# 版本历史：
#   v6.5.7 - 交互优化：移除高级编辑器中的冗余选项
#   v6.5.6 - 紧急修复：修复代码乱码、只读变量写入错误
#   ...

# --- 严格模式与环境设定 ---
set -euo pipefail
IFS=$'\n\t'

# --- 退出码常量定义 ---
readonly ERR_OK=0
readonly ERR_USAGE=2
readonly ERR_DEPENDENCY=3
readonly ERR_PERMISSION=4
readonly ERR_CONFIG=5
readonly ERR_CRYPTO=6
readonly ERR_RUNTIME=10

# --- 脚本元数据 ---
readonly SCRIPT_VERSION="v6.5.7"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CONFIG_FILE="$HOME/.docker-auto-update-watchtower.conf"
readonly ENV_FILE="${SCRIPT_DIR}/watchtower.env"
readonly ENV_FILE_LAST_RUN="${SCRIPT_DIR}/watchtower.env.last_run"
readonly WATCHTOWER_CONTAINER_NAME="watchtower"
readonly WATCHTOWER_BACKUP_CONTAINER_NAME="watchtower-backup"
readonly WATCHTOWER_DOCKER_NAMES_FORMAT='{{.Names}}'
readonly WATCHTOWER_INSPECT_ENV_FORMAT='{{json .Config.Env}}'
readonly WATCHTOWER_INSPECT_CMD_FORMAT='{{json .Config.Cmd}}'
readonly WATCHTOWER_INSPECT_CREATED_FORMAT='{{.Created}}'

# --- 全局会话密码变量 ---
SESSION_ENCRYPTION_PASSWORD=""

readonly WATCHTOWER_DEFAULT_INTERVAL_SECONDS="21600"
readonly WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES="true"

# --- 全局临时文件管理 ---
declare -a TEMP_FILES=()
_cleanup_temp_files() {
	if [ ${#TEMP_FILES[@]} -gt 0 ]; then
		rm -f "${TEMP_FILES[@]}" 2>/dev/null || true
	fi
}
trap _cleanup_temp_files EXIT INT TERM

# --- 参数验证函数 ---
watchtower_validate_args() {
	local arg="${1:-}"
	case "$arg" in
	"" | --run-once | --systemd-start | --systemd-stop | --generate-systemd-service | --diagnose | --export-config | --import-config)
		return "${ERR_OK}"
		;;
	--help | -h)
		echo "Usage: $0 [command]"
		echo "Commands:"
		echo "  (no command)              Enter interactive menu"
		echo "  --run-once                Execute a single scan and exit"
		echo "  --systemd-start           Start the service (for systemd)"
		echo "  --systemd-stop            Stop the service (for systemd)"
		echo "  --generate-systemd-service  Deprecated no-op (systemd file generation removed)"
		echo "  --diagnose                Print runtime diagnostics"
		echo "  --export-config           Export current config to timestamp file"
		echo "  --import-config <file>    Import config from specified file"
		exit "${ERR_OK}"
		;;
	*)
		log_error "未知参数: $arg"
		echo "Usage: $0 [--run-once|--systemd-start|--systemd-stop|--generate-systemd-service(deprecated)|--diagnose|--export-config|--import-config <file>]" >&2
		exit "${ERR_USAGE}"
		;;
	esac
}

# --- 日志函数封装 ---
log_info() { echo "[INFO] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_success() { echo "[SUCCESS] $*" >&2; }

if [ -f "/opt/vps_install_modules/utils.sh" ]; then
	# shellcheck source=/dev/null
	source "/opt/vps_install_modules/utils.sh"
fi

if [ -f "${SCRIPT_DIR}/../utils.sh" ] && ! declare -f should_clear_screen &>/dev/null; then
	# shellcheck source=/dev/null
	source "${SCRIPT_DIR}/../utils.sh"
fi

if ! declare -f should_clear_screen &>/dev/null; then
	declare -A WATCHTOWER_SMART_CLEAR_SEEN=()
	should_clear_screen() {
		local menu_key="${1:-watchtower:default}"
		local mode="${JB_CLEAR_MODE:-off}"
		case "$mode" in
		full | true) return 0 ;;
		smart)
			if [ -n "${WATCHTOWER_SMART_CLEAR_SEEN[$menu_key]+x}" ]; then return 1; fi
			WATCHTOWER_SMART_CLEAR_SEEN["$menu_key"]=1
			return 0
			;;
		*) return 1 ;;
		esac
	}
fi

# --- 颜色变量 ---
if ! declare -p GREEN >/dev/null 2>&1; then GREEN=""; fi
if ! declare -p NC >/dev/null 2>&1; then NC=""; fi
if ! declare -p RED >/dev/null 2>&1; then RED=""; fi
if ! declare -p YELLOW >/dev/null 2>&1; then YELLOW=""; fi
if ! declare -p CYAN >/dev/null 2>&1; then CYAN=""; fi
if ! declare -p BLUE >/dev/null 2>&1; then BLUE=""; fi
if ! declare -p ORANGE >/dev/null 2>&1; then ORANGE=""; fi
if [ -z "$GREEN" ] && [ -t 1 ] && command -v tput &>/dev/null; then
	GREEN=$(tput setaf 2)
	RED=$(tput setaf 1)
	YELLOW=$(tput setaf 3)
	CYAN=$(tput setaf 6)
	BLUE=$(tput setaf 4)
	ORANGE=$(tput setaf 166)
	NC=$(tput sgr0)
fi

if ! declare -f _render_menu &>/dev/null; then
	_render_menu() {
		local title="$1"
		shift
		printf '%b\n' "\n${BLUE}--- $title ---${NC}"
		printf " %s\n" "$@"
	}
fi

if ! declare -f _prompt_user_input &>/dev/null; then
	_prompt_user_input() {
		local prompt="$1"
		local def_val="${2:-}"
		local val
		if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
			echo "$def_val"
			return 0
		fi
		read -r -p "${prompt}" val </dev/tty
		echo "${val:-$def_val}"
	}
fi

if ! declare -f _prompt_for_menu_choice &>/dev/null; then
	_prompt_for_menu_choice() {
		local prompt="$1"
		local val
		if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
			log_error "非交互模式无法选择菜单"
			return 1
		fi
		local start="" end="" range_is_numeric="false"
		if [[ "$prompt" =~ ^[0-9]+-[0-9]+$ ]]; then
			start="${prompt%%-*}"
			end="${prompt##*-}"
			range_is_numeric="true"
		fi
		while true; do
			read -r -p "请选择 [${prompt}]: " val </dev/tty
			if [ -z "$val" ]; then
				echo ""
				return 0
			fi
			if [ "$range_is_numeric" = "true" ]; then
				if ! [[ "$val" =~ ^[0-9]+$ ]]; then
					log_error "无效选项"
					continue
				fi
				if [ "$val" -lt "$start" ] || [ "$val" -gt "$end" ]; then
					log_error "无效选项"
					continue
				fi
				echo "$val"
				return 0
			fi
			if [[ "$val" =~ ^[0-9A-Za-z]+$ ]]; then
				echo "$val"
				return 0
			fi
			log_error "无效选项"
		done
	}
fi

if ! declare -f press_enter_to_continue &>/dev/null; then
	press_enter_to_continue() {
		if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
			return 0
		fi
		read -r -p "按 Enter 继续..." </dev/tty
	}
fi

if ! declare -f confirm_action &>/dev/null; then
	confirm_action() {
		local prompt="$1"
		local choice
		if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
			log_error "非交互模式无法确认"
			return 1
		fi
		read -r -p "${prompt} ([y]/n): " choice </dev/tty
		case "$choice" in n | N) return 1 ;; *) return 0 ;; esac
	}
fi

# --- 通用工具函数 ---
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

# --- Sudo 兜底函数 ---
if ! declare -f run_with_sudo &>/dev/null; then
	run_with_sudo() {
		if [ "$(id -u)" -eq 0 ]; then "$@"; else
			if command -v sudo &>/dev/null; then
				if sudo -n true 2>/dev/null; then
					sudo -n "$@"
					return $?
				fi
				if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
					log_error "非交互模式下无法获取 sudo 权限"
					return "${ERR_PERMISSION}"
				fi
				sudo "$@"
			else
				log_error "需要 root 权限执行此操作，且未找到 sudo 命令。"
				return "${ERR_PERMISSION}"
			fi
		fi
	}
fi

init_runtime() {
	sanitize_noninteractive_flag
}

self_elevate_or_die() {
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi

	if ! command -v sudo >/dev/null 2>&1; then
		log_error "未安装 sudo，无法自动提权。"
		exit "${ERR_PERMISSION}"
	fi

	case "$0" in
	/dev/fd/* | /proc/self/fd/*)
		local tmp_script
		tmp_script=$(mktemp /tmp/watchtower_module.XXXXXX.sh)
		cat <"$0" >"$tmp_script"
		chmod 700 "$tmp_script" || true
		if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
			if sudo -n true 2>/dev/null; then
				exec sudo -n -E bash "$tmp_script" "$@"
			fi
			log_error "非交互模式下无法自动提权（需要免密 sudo）。"
			exit "${ERR_PERMISSION}"
		fi
		exec sudo -E bash "$tmp_script" "$@"
		;;
	*)
		if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
			if sudo -n true 2>/dev/null; then
				exec sudo -n -E bash "$0" "$@"
			fi
			log_error "非交互模式下无法自动提权（需要免密 sudo）。"
			exit "${ERR_PERMISSION}"
		fi
		exec sudo -E bash "$0" "$@"
		;;
	esac
}

# --- 辅助函数：遮蔽字符串 ---
_mask_string() {
	local str="$1"
	local visible="$2"
	if [ -z "$str" ]; then
		echo ""
		return
	fi
	local len=${#str}
	if [ "$len" -le "$visible" ]; then
		echo "$str"
	else
		local start
		start=$(echo "$str" | cut -c1-"$visible")
		local end
		end=$(echo "$str" | tail -c 4)
		echo "${start}...${end}"
	fi
}

_sanitize_input_text() {
	local raw="${1:-}"
	raw=$(printf '%s' "$raw" | tr -d '\000-\010\013\014\016-\037\177')
	printf '%s' "$raw"
}

# --- 模块变量 ---
TG_BOT_TOKEN=""
ENCRYPTED_TG_BOT_TOKEN=""
CONFIG_ENCRYPTED="false"
TG_CHAT_ID=""
WATCHTOWER_EXCLUDE_LIST=""
WATCHTOWER_EXTRA_ARGS=""
WATCHTOWER_DEBUG_ENABLED=""
WATCHTOWER_CONFIG_INTERVAL=""
WATCHTOWER_ENABLED=""
WATCHTOWER_HOST_ALIAS=""
WATCHTOWER_RUN_MODE=""
WATCHTOWER_SCHEDULE_CRON=""
WATCHTOWER_IPV4_INTERFACE=""
WATCHTOWER_IPV6_INTERFACE=""
WATCHTOWER_IMAGE_PRIMARY_REPO=""
WATCHTOWER_IMAGE_FALLBACK_REPO=""
WATCHTOWER_IMAGE_TAG=""
WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK=""
WATCHTOWER_DOCKER_API_VERSION=""
WATCHTOWER_NOTIFY_ON_NO_UPDATES=""

# --- 加密相关函数 ---
_get_encryption_password() {
	if [ -n "$SESSION_ENCRYPTION_PASSWORD" ]; then return; fi
	log_info "配置已加密，请输入密码以解密会话。"
	read -r -s -p "请输入密码: " SESSION_ENCRYPTION_PASSWORD
	echo
	if [ -z "$SESSION_ENCRYPTION_PASSWORD" ]; then
		log_error "密码不能为空！"
		exit "${ERR_CRYPTO}"
	fi
}

# --- 配置加载与保存 ---
_parse_config_value() {
	local raw="${1:-}"
	if [[ "$raw" =~ ^\"(.*)\"$ ]]; then
		raw="${BASH_REMATCH[1]}"
		raw="${raw//\\\"/\"}"
		raw="${raw//\\\\/\\}"
	fi
	printf '%s' "$raw"
}

_apply_config_kv() {
	local key="${1:-}"
	local value="${2:-}"

	case "$key" in
	CONFIG_ENCRYPTED | ENCRYPTED_TG_BOT_TOKEN | TG_BOT_TOKEN | TG_CHAT_ID)
		printf -v "$key" '%s' "$value"
		return 0
		;;
	WATCHTOWER_*)
		if [[ "$key" =~ ^WATCHTOWER_[A-Za-z0-9_]+$ ]]; then
			printf -v "$key" '%s' "$value"
			return 0
		fi
		;;
	esac

	return 1
}

_normalize_bool_value() {
	local raw_value="${1:-}"
	local default_value="${2:-false}"
	case "$raw_value" in
	true | TRUE | True | 1 | yes | YES | Yes | on | ON | On) printf '%s' "true" ;;
	false | FALSE | False | 0 | no | NO | No | off | OFF | Off) printf '%s' "false" ;;
	"") printf '%s' "$default_value" ;;
	*)
		log_warn "布尔配置值非法: ${raw_value}，已回退为 ${default_value}"
		printf '%s' "$default_value"
		;;
	esac
}

_is_watchtower_bool_value() {
	case "${1:-}" in
	true | TRUE | True | 1 | yes | YES | Yes | on | ON | On | false | FALSE | False | 0 | no | NO | No | off | OFF | Off) return 0 ;;
	*) return 1 ;;
	esac
}

_validate_watchtower_identifier_value() {
	local value="${1:-}"
	local pattern="${2:-^[A-Za-z0-9._:-]+$}"
	[ -z "$value" ] && return 0
	[[ "$value" =~ $pattern ]]
}

_validate_watchtower_runtime_state() {
	case "${WATCHTOWER_RUN_MODE:-interval}" in
	interval | cron | aligned) ;;
	*)
		log_error "Watchtower 运行模式无效: ${WATCHTOWER_RUN_MODE:-}"
		return "${ERR_CONFIG}"
		;;
	esac

	if [[ "${WATCHTOWER_RUN_MODE:-interval}" == "interval" ]]; then
		if ! [[ "${WATCHTOWER_CONFIG_INTERVAL:-}" =~ ^[1-9][0-9]*$ ]]; then
			log_error "Watchtower 检测间隔无效: ${WATCHTOWER_CONFIG_INTERVAL:-}"
			return "${ERR_CONFIG}"
		fi
	fi

	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IMAGE_PRIMARY_REPO:-}" '^[A-Za-z0-9./:_-]+$'; then
		log_error "Watchtower 主镜像仓库配置无效: ${WATCHTOWER_IMAGE_PRIMARY_REPO:-}"
		return "${ERR_CONFIG}"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IMAGE_FALLBACK_REPO:-}" '^[A-Za-z0-9./:_-]+$'; then
		log_error "Watchtower 回退镜像仓库配置无效: ${WATCHTOWER_IMAGE_FALLBACK_REPO:-}"
		return "${ERR_CONFIG}"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IMAGE_TAG:-}" '^[A-Za-z0-9._-]+$'; then
		log_error "Watchtower 镜像标签配置无效: ${WATCHTOWER_IMAGE_TAG:-}"
		return "${ERR_CONFIG}"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_DOCKER_API_VERSION:-}" '^[0-9]+(\.[0-9]+)?$'; then
		log_error "Watchtower Docker API 版本配置无效: ${WATCHTOWER_DOCKER_API_VERSION:-}"
		return "${ERR_CONFIG}"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_HOST_ALIAS:-}" '^[A-Za-z0-9._-]+$'; then
		log_error "Watchtower 主机别名配置无效: ${WATCHTOWER_HOST_ALIAS:-}"
		return "${ERR_CONFIG}"
	fi
	if [ -n "${WATCHTOWER_HOST_ALIAS:-}" ] && [ "${#WATCHTOWER_HOST_ALIAS}" -gt 15 ]; then
		log_error "Watchtower 主机别名过长: ${WATCHTOWER_HOST_ALIAS}"
		return "${ERR_CONFIG}"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IPV4_INTERFACE:-}" '^[A-Za-z0-9_.:-]+$'; then
		log_error "Watchtower IPv4 接口配置无效: ${WATCHTOWER_IPV4_INTERFACE:-}"
		return "${ERR_CONFIG}"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IPV6_INTERFACE:-}" '^[A-Za-z0-9_.:-]+$'; then
		log_error "Watchtower IPv6 接口配置无效: ${WATCHTOWER_IPV6_INTERFACE:-}"
		return "${ERR_CONFIG}"
	fi

	return "${ERR_OK}"
}

_repair_watchtower_loaded_config() {
	if ! [[ "${WATCHTOWER_CONFIG_INTERVAL:-}" =~ ^[1-9][0-9]*$ ]]; then
		log_warn "Watchtower 检测间隔非法，已回退默认值: ${WATCHTOWER_CONFIG_INTERVAL:-}"
		WATCHTOWER_CONFIG_INTERVAL="${WATCHTOWER_CONF_DEFAULT_INTERVAL:-${WATCHTOWER_DEFAULT_INTERVAL_SECONDS}}"
		if ! [[ "$WATCHTOWER_CONFIG_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
			WATCHTOWER_CONFIG_INTERVAL="${WATCHTOWER_DEFAULT_INTERVAL_SECONDS}"
		fi
	fi

	case "${WATCHTOWER_RUN_MODE:-interval}" in
	interval | cron | aligned) ;;
	*)
		log_warn "Watchtower 运行模式非法，已回退为 interval: ${WATCHTOWER_RUN_MODE:-}"
		WATCHTOWER_RUN_MODE="interval"
		WATCHTOWER_SCHEDULE_CRON=""
		;;
	esac

	if [[ "$WATCHTOWER_RUN_MODE" == "cron" || "$WATCHTOWER_RUN_MODE" == "aligned" ]] && [ -n "$WATCHTOWER_SCHEDULE_CRON" ]; then
		if ! _validate_watchtower_cron_expression "$WATCHTOWER_SCHEDULE_CRON"; then
			log_warn "Watchtower Cron 配置非法，已回退为 interval: ${WATCHTOWER_SCHEDULE_CRON}"
			WATCHTOWER_RUN_MODE="interval"
			WATCHTOWER_SCHEDULE_CRON=""
		fi
	fi

	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IMAGE_PRIMARY_REPO:-}" '^[A-Za-z0-9./:_-]+$'; then
		log_warn "Watchtower 主镜像仓库非法，已回退默认值: ${WATCHTOWER_IMAGE_PRIMARY_REPO:-}"
		WATCHTOWER_IMAGE_PRIMARY_REPO="ghcr.io/containrrr/watchtower"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IMAGE_FALLBACK_REPO:-}" '^[A-Za-z0-9./:_-]+$'; then
		log_warn "Watchtower 回退镜像仓库非法，已回退默认值: ${WATCHTOWER_IMAGE_FALLBACK_REPO:-}"
		WATCHTOWER_IMAGE_FALLBACK_REPO="containrrr/watchtower"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IMAGE_TAG:-}" '^[A-Za-z0-9._-]+$'; then
		log_warn "Watchtower 镜像标签非法，已回退默认值: ${WATCHTOWER_IMAGE_TAG:-}"
		WATCHTOWER_IMAGE_TAG="latest"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_DOCKER_API_VERSION:-}" '^[0-9]+(\.[0-9]+)?$'; then
		log_warn "Watchtower Docker API 版本非法，已回退自动检测: ${WATCHTOWER_DOCKER_API_VERSION:-}"
		WATCHTOWER_DOCKER_API_VERSION=""
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_HOST_ALIAS:-}" '^[A-Za-z0-9._-]+$'; then
		log_warn "Watchtower 主机别名非法，已回退默认值: ${WATCHTOWER_HOST_ALIAS:-}"
		WATCHTOWER_HOST_ALIAS="DockerNode"
	fi
	if [ -n "${WATCHTOWER_HOST_ALIAS:-}" ] && [ "${#WATCHTOWER_HOST_ALIAS}" -gt 15 ]; then
		log_warn "Watchtower 主机别名过长，已回退默认值: ${WATCHTOWER_HOST_ALIAS}"
		WATCHTOWER_HOST_ALIAS="DockerNode"
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IPV4_INTERFACE:-}" '^[A-Za-z0-9_.:-]+$'; then
		log_warn "Watchtower IPv4 接口非法，已清空: ${WATCHTOWER_IPV4_INTERFACE:-}"
		WATCHTOWER_IPV4_INTERFACE=""
	fi
	if ! _validate_watchtower_identifier_value "${WATCHTOWER_IPV6_INTERFACE:-}" '^[A-Za-z0-9_.:-]+$'; then
		log_warn "Watchtower IPv6 接口非法，已清空: ${WATCHTOWER_IPV6_INTERFACE:-}"
		WATCHTOWER_IPV6_INTERFACE=""
	fi
}

_watchtower_cron_number_in_range() {
	local value="${1:-}"
	local min_value="${2:-0}"
	local max_value="${3:-0}"
	[[ "$value" =~ ^[0-9]+$ ]] || return 1
	[ "$value" -ge "$min_value" ] && [ "$value" -le "$max_value" ]
}

_validate_watchtower_cron_field() {
	local field_value="${1:-}"
	local min_value="${2:-0}"
	local max_value="${3:-0}"
	local old_ifs="${IFS:-}"
	local part=""
	local range_start=""
	local range_end=""
	local step_value=""

	[ -n "$field_value" ] || return 1
	IFS=','
	read -r -a _watchtower_cron_parts <<<"$field_value"
	IFS="$old_ifs"

	for part in "${_watchtower_cron_parts[@]}"; do
		[ -n "$part" ] || return 1
		case "$part" in
		\*)
			continue
			;;
		\*/[0-9]*)
			step_value="${part#*/}"
			_watchtower_cron_number_in_range "$step_value" 1 "$max_value" || return 1
			continue
			;;
		esac

		if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
			range_start="${BASH_REMATCH[1]}"
			range_end="${BASH_REMATCH[2]}"
			_watchtower_cron_number_in_range "$range_start" "$min_value" "$max_value" || return 1
			_watchtower_cron_number_in_range "$range_end" "$min_value" "$max_value" || return 1
			[ "$range_start" -le "$range_end" ] || return 1
			continue
		fi

		_watchtower_cron_number_in_range "$part" "$min_value" "$max_value" || return 1
	done

	return 0
}

_validate_watchtower_cron_expression() {
	local cron_expr="${1:-}"
	local sec=""
	local min=""
	local hour=""
	local day=""
	local month=""
	local dow=""
	local extra=""
	local old_ifs="${IFS:-}"

	IFS=' '
	read -r sec min hour day month dow extra <<<"$cron_expr"
	IFS="$old_ifs"
	if [ -n "$extra" ] || [ -z "$sec" ] || [ -z "$min" ] || [ -z "$hour" ] || [ -z "$day" ] || [ -z "$month" ] || [ -z "$dow" ]; then
		return 1
	fi

	_validate_watchtower_cron_field "$sec" 0 59 || return 1
	_validate_watchtower_cron_field "$min" 0 59 || return 1
	_validate_watchtower_cron_field "$hour" 0 23 || return 1
	_validate_watchtower_cron_field "$day" 1 31 || return 1
	_validate_watchtower_cron_field "$month" 1 12 || return 1
	_validate_watchtower_cron_field "$dow" 0 7 || return 1
	return 0
}

_load_watchtower_module_defaults() {
	local default_interval="${WATCHTOWER_CONF_DEFAULT_INTERVAL:-${WATCHTOWER_DEFAULT_INTERVAL_SECONDS}}"
	if ! [[ "$default_interval" =~ ^[0-9]+$ ]] || [ "$default_interval" -le 0 ]; then
		default_interval="${WATCHTOWER_DEFAULT_INTERVAL_SECONDS}"
	fi

	WATCHTOWER_EXCLUDE_LIST="${WATCHTOWER_CONF_EXCLUDE_CONTAINERS:-}"
	WATCHTOWER_CONFIG_INTERVAL="$default_interval"
	WATCHTOWER_NOTIFY_ON_NO_UPDATES="$(_normalize_bool_value "${WATCHTOWER_CONF_NOTIFY_ON_NO_UPDATES:-}" "${WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES}")"
}

load_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		_load_watchtower_module_defaults
		WATCHTOWER_EXTRA_ARGS=""
		WATCHTOWER_ENABLED="false"
		WATCHTOWER_HOST_ALIAS=$(hostname | cut -d'.' -f1 | tr -d '\n')
		[ "${#WATCHTOWER_HOST_ALIAS}" -gt 15 ] && WATCHTOWER_HOST_ALIAS="DockerNode"
		WATCHTOWER_RUN_MODE="interval"
		WATCHTOWER_DEBUG_ENABLED="false"
		WATCHTOWER_SCHEDULE_CRON=""
		WATCHTOWER_IPV4_INTERFACE=""
		WATCHTOWER_IPV6_INTERFACE=""
		WATCHTOWER_IMAGE_PRIMARY_REPO="ghcr.io/containrrr/watchtower"
		WATCHTOWER_IMAGE_FALLBACK_REPO="containrrr/watchtower"
		WATCHTOWER_IMAGE_TAG="latest"
		WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK="true"
		WATCHTOWER_DOCKER_API_VERSION=""
		return
	fi

	local key=""
	local raw_value=""
	local parsed_value=""
	while IFS= read -r line || [ -n "$line" ]; do
		[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
		if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
			key="${BASH_REMATCH[1]}"
			raw_value="${BASH_REMATCH[2]}"
			parsed_value="$(_parse_config_value "$raw_value")"
			_apply_config_kv "$key" "$parsed_value" || true
		fi
	done <"$CONFIG_FILE"

	if [ "${CONFIG_ENCRYPTED}" = "true" ] && [ -n "${ENCRYPTED_TG_BOT_TOKEN}" ]; then
		if ! command -v openssl &>/dev/null; then
			log_error "检测到加密配置，但未找到 openssl 命令，无法解密！"
			exit "${ERR_DEPENDENCY}"
		fi
		_get_encryption_password
		local decrypted_token
		decrypted_token=$(echo "${ENCRYPTED_TG_BOT_TOKEN}" | openssl enc -aes-256-cbc -a -d -pbkdf2 -pass pass:"${SESSION_ENCRYPTION_PASSWORD}" 2>/dev/null || true)
		if [ -z "$decrypted_token" ]; then
			log_error "解密失败！密码错误或令牌已损坏。"
			SESSION_ENCRYPTION_PASSWORD=""
			exit "${ERR_CRYPTO}"
		fi
		TG_BOT_TOKEN="$decrypted_token"
	fi

	WATCHTOWER_EXCLUDE_LIST="${WATCHTOWER_EXCLUDE_LIST:-}"
	WATCHTOWER_EXTRA_ARGS="${WATCHTOWER_EXTRA_ARGS:-}"
	WATCHTOWER_DEBUG_ENABLED="${WATCHTOWER_DEBUG_ENABLED:-false}"
	WATCHTOWER_CONFIG_INTERVAL="${WATCHTOWER_CONFIG_INTERVAL:-${WATCHTOWER_CONF_DEFAULT_INTERVAL:-${WATCHTOWER_DEFAULT_INTERVAL_SECONDS}}}"
	WATCHTOWER_ENABLED="${WATCHTOWER_ENABLED:-false}"
	[ -z "$WATCHTOWER_HOST_ALIAS" ] && WATCHTOWER_HOST_ALIAS=$(hostname | cut -d'.' -f1 | tr -d '\n')

	if [ "${#WATCHTOWER_HOST_ALIAS}" -gt 15 ]; then
		WATCHTOWER_HOST_ALIAS="DockerNode"
	fi

	WATCHTOWER_RUN_MODE="${WATCHTOWER_RUN_MODE:-interval}"
	WATCHTOWER_SCHEDULE_CRON="${WATCHTOWER_SCHEDULE_CRON:-}"
	WATCHTOWER_IPV4_INTERFACE="${WATCHTOWER_IPV4_INTERFACE:-}"
	WATCHTOWER_IPV6_INTERFACE="${WATCHTOWER_IPV6_INTERFACE:-}"
	WATCHTOWER_IMAGE_PRIMARY_REPO="${WATCHTOWER_IMAGE_PRIMARY_REPO:-ghcr.io/containrrr/watchtower}"
	WATCHTOWER_IMAGE_FALLBACK_REPO="${WATCHTOWER_IMAGE_FALLBACK_REPO:-containrrr/watchtower}"
	WATCHTOWER_IMAGE_TAG="${WATCHTOWER_IMAGE_TAG:-latest}"
	WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK="${WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK:-true}"
	WATCHTOWER_DOCKER_API_VERSION="${WATCHTOWER_DOCKER_API_VERSION:-}"
	WATCHTOWER_NOTIFY_ON_NO_UPDATES="$(_normalize_bool_value "${WATCHTOWER_NOTIFY_ON_NO_UPDATES:-${WATCHTOWER_CONF_NOTIFY_ON_NO_UPDATES:-}}" "${WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES}")"
	_repair_watchtower_loaded_config

	if [ -n "${WATCHTOWER_EXCLUDE_LIST:-}" ]; then
		local old_ifs migrated_list=""
		old_ifs="${IFS:-}"
		IFS=',' read -r -a _exclude_items <<<"${WATCHTOWER_EXCLUDE_LIST}"
		IFS="${old_ifs}"
		local item normalized
		for item in "${_exclude_items[@]}"; do
			normalized="$(printf '%s' "$item" | tr -d '[:space:]')"
			[ -z "$normalized" ] && continue
			case "$normalized" in
			portainer | portainer_agent) ;;
			*)
				if [ -z "$migrated_list" ]; then
					migrated_list="$normalized"
				else
					migrated_list+=" ,$normalized"
				fi
				;;
			esac
		done
		WATCHTOWER_EXCLUDE_LIST="${migrated_list// /}"
	fi
}

save_config() {
	mkdir -p "$(dirname "$CONFIG_FILE")"

	local temp_config
	temp_config=$(mktemp)
	TEMP_FILES+=("$temp_config")

	local final_encrypted_token=""
	local plain_token_to_write="${TG_BOT_TOKEN}"
	if [ "${CONFIG_ENCRYPTED}" = "true" ]; then
		if ! command -v openssl &>/dev/null; then
			log_error "需要 openssl 来加密配置，请先安装。"
			return "${ERR_DEPENDENCY}"
		fi
		if [ -n "${TG_BOT_TOKEN}" ]; then
			_get_encryption_password
			final_encrypted_token=$(echo "${TG_BOT_TOKEN}" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"${SESSION_ENCRYPTION_PASSWORD}")
		else
			final_encrypted_token=""
		fi
		plain_token_to_write=""
	fi

	cat >"$temp_config" <<EOF
CONFIG_ENCRYPTED="${CONFIG_ENCRYPTED}"
ENCRYPTED_TG_BOT_TOKEN="${final_encrypted_token}"
TG_BOT_TOKEN="${plain_token_to_write}"
TG_CHAT_ID="${TG_CHAT_ID}"
WATCHTOWER_EXCLUDE_LIST="${WATCHTOWER_EXCLUDE_LIST}"
WATCHTOWER_EXTRA_ARGS="${WATCHTOWER_EXTRA_ARGS}"
WATCHTOWER_DEBUG_ENABLED="${WATCHTOWER_DEBUG_ENABLED}"
WATCHTOWER_CONFIG_INTERVAL="${WATCHTOWER_CONFIG_INTERVAL}"
WATCHTOWER_ENABLED="${WATCHTOWER_ENABLED}"
WATCHTOWER_HOST_ALIAS="${WATCHTOWER_HOST_ALIAS}"
WATCHTOWER_RUN_MODE="${WATCHTOWER_RUN_MODE}"
WATCHTOWER_SCHEDULE_CRON="${WATCHTOWER_SCHEDULE_CRON}"
WATCHTOWER_IPV4_INTERFACE="${WATCHTOWER_IPV4_INTERFACE}"
WATCHTOWER_IPV6_INTERFACE="${WATCHTOWER_IPV6_INTERFACE}"
WATCHTOWER_IMAGE_PRIMARY_REPO="${WATCHTOWER_IMAGE_PRIMARY_REPO}"
WATCHTOWER_IMAGE_FALLBACK_REPO="${WATCHTOWER_IMAGE_FALLBACK_REPO}"
WATCHTOWER_IMAGE_TAG="${WATCHTOWER_IMAGE_TAG}"
WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK="${WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK}"
WATCHTOWER_DOCKER_API_VERSION="${WATCHTOWER_DOCKER_API_VERSION}"
WATCHTOWER_NOTIFY_ON_NO_UPDATES="${WATCHTOWER_NOTIFY_ON_NO_UPDATES}"
EOF

	chmod 600 "$temp_config"
	mv "$temp_config" "$CONFIG_FILE" || log_warn "移动配置文件失败"
}

watchtower_export_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		log_warn "未找到配置文件: ${CONFIG_FILE}"
		return "${ERR_CONFIG}"
	fi
	local out_file
	out_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
	cp -f "$CONFIG_FILE" "$out_file"
	chmod 600 "$out_file" || true
	log_success "配置已导出: ${out_file}"
	return "${ERR_OK}"
}

_validate_watchtower_import_candidate() {
	local candidate_file="${1:-}"
	local validation_env_file=""
	[ -n "$candidate_file" ] && [ -f "$candidate_file" ] || return "${ERR_CONFIG}"

	validation_env_file=$(mktemp)
	TEMP_FILES+=("$validation_env_file")

	(
		CONFIG_ENCRYPTED="false"
		ENCRYPTED_TG_BOT_TOKEN=""
		TG_BOT_TOKEN=""
		TG_CHAT_ID=""
		_load_watchtower_module_defaults
		WATCHTOWER_EXTRA_ARGS=""
		WATCHTOWER_DEBUG_ENABLED="false"
		WATCHTOWER_ENABLED="false"
		WATCHTOWER_HOST_ALIAS="DockerNode"
		WATCHTOWER_RUN_MODE="interval"
		WATCHTOWER_SCHEDULE_CRON=""
		WATCHTOWER_IPV4_INTERFACE=""
		WATCHTOWER_IPV6_INTERFACE=""
		WATCHTOWER_IMAGE_PRIMARY_REPO="ghcr.io/containrrr/watchtower"
		WATCHTOWER_IMAGE_FALLBACK_REPO="containrrr/watchtower"
		WATCHTOWER_IMAGE_TAG="latest"
		WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK="true"
		WATCHTOWER_DOCKER_API_VERSION=""
		WATCHTOWER_NOTIFY_ON_NO_UPDATES="${WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES}"

		local line=""
		local key=""
		local raw_value=""
		local parsed_value=""
		while IFS= read -r line || [ -n "$line" ]; do
			[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
			if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
				log_error "导入配置格式无效: $line"
				exit "${ERR_CONFIG}"
			fi
			key="${BASH_REMATCH[1]}"
			raw_value="${BASH_REMATCH[2]}"
			parsed_value="$(_parse_config_value "$raw_value")"
			_apply_config_kv "$key" "$parsed_value" || true
		done <"$candidate_file"

		if ! _is_watchtower_bool_value "${WATCHTOWER_DEBUG_ENABLED:-false}"; then
			log_error "导入配置中的调试开关无效: ${WATCHTOWER_DEBUG_ENABLED:-}"
			exit "${ERR_CONFIG}"
		fi
		if ! _is_watchtower_bool_value "${WATCHTOWER_ENABLED:-false}"; then
			log_error "导入配置中的启用开关无效: ${WATCHTOWER_ENABLED:-}"
			exit "${ERR_CONFIG}"
		fi
		if ! _is_watchtower_bool_value "${WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK:-true}"; then
			log_error "导入配置中的本地镜像回退开关无效: ${WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK:-}"
			exit "${ERR_CONFIG}"
		fi
		if ! _is_watchtower_bool_value "${WATCHTOWER_NOTIFY_ON_NO_UPDATES:-${WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES}}"; then
			log_error "导入配置中的无更新通知开关无效: ${WATCHTOWER_NOTIFY_ON_NO_UPDATES:-}"
			exit "${ERR_CONFIG}"
		fi

		WATCHTOWER_DEBUG_ENABLED="$(_normalize_bool_value "${WATCHTOWER_DEBUG_ENABLED:-}" "false")"
		WATCHTOWER_ENABLED="$(_normalize_bool_value "${WATCHTOWER_ENABLED:-}" "false")"
		WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK="$(_normalize_bool_value "${WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK:-}" "true")"
		WATCHTOWER_NOTIFY_ON_NO_UPDATES="$(_normalize_bool_value "${WATCHTOWER_NOTIFY_ON_NO_UPDATES:-}" "${WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES}")"

		if ! _validate_watchtower_runtime_state; then
			exit "${ERR_CONFIG}"
		fi

		if [ -n "$WATCHTOWER_EXTRA_ARGS" ]; then
			if ! _parse_watchtower_extra_args >/dev/null; then
				exit "${ERR_CONFIG}"
			fi
		fi

		if [[ "$WATCHTOWER_RUN_MODE" == "cron" || "$WATCHTOWER_RUN_MODE" == "aligned" ]] && [ -n "$WATCHTOWER_SCHEDULE_CRON" ]; then
			_validate_watchtower_cron_expression "$WATCHTOWER_SCHEDULE_CRON" || {
				log_error "导入配置中的 Cron 表达式无效: ${WATCHTOWER_SCHEDULE_CRON}"
				exit "${ERR_CONFIG}"
			}
		fi

		if ! _generate_env_file "$validation_env_file" >/dev/null; then
			exit "${ERR_CONFIG}"
		fi
	)
}

watchtower_import_config() {
	local in_file="${1:-}"
	local staged_config=""
	if [ -z "$in_file" ] || [ ! -f "$in_file" ]; then
		log_error "导入文件不存在: ${in_file}"
		return "${ERR_CONFIG}"
	fi
	staged_config=$(mktemp)
	TEMP_FILES+=("$staged_config")
	mkdir -p "$(dirname "$CONFIG_FILE")"
	cp -f "$in_file" "$staged_config"
	chmod 600 "$staged_config" || true
	if ! _validate_watchtower_import_candidate "$staged_config"; then
		log_error "导入配置校验失败，已保留当前配置。"
		return "${ERR_CONFIG}"
	fi
	mv -f "$staged_config" "$CONFIG_FILE"
	chmod 600 "$CONFIG_FILE" || true
	log_success "配置已导入: ${CONFIG_FILE}"
	return "${ERR_OK}"
}

watchtower_diagnose() {
	load_config
	printf 'watchtower_script_version=%s\n' "$SCRIPT_VERSION"
	printf 'config_file=%s\n' "$CONFIG_FILE"
	printf 'watchtower_image_primary_repo=%s\n' "${WATCHTOWER_IMAGE_PRIMARY_REPO}"
	printf 'watchtower_image_fallback_repo=%s\n' "${WATCHTOWER_IMAGE_FALLBACK_REPO}"
	printf 'watchtower_image_tag=%s\n' "${WATCHTOWER_IMAGE_TAG}"
	printf 'watchtower_allow_local_image_fallback=%s\n' "${WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK}"
	printf 'watchtower_docker_api_version_configured=%s\n' "${WATCHTOWER_DOCKER_API_VERSION:-auto}"
	if [ -f "$CONFIG_FILE" ]; then
		printf 'config_exists=yes\n'
	else
		printf 'config_exists=no\n'
	fi
	if command -v docker >/dev/null 2>&1; then
		local effective_api_version=""
		effective_api_version=$(_resolve_watchtower_docker_api_version 2>/dev/null || true)
		printf 'docker=present\n'
		printf 'watchtower_docker_api_version_effective=%s\n' "${effective_api_version:-unresolved}"
		if _watchtower_is_running 2>/dev/null; then
			printf 'watchtower_container=running\n'
		else
			printf 'watchtower_container=not_running\n'
		fi
	else
		printf 'docker=missing\n'
		printf 'watchtower_container=n/a\n'
	fi
	return "${ERR_OK}"
}

# --- 增强的 IP 地址获取函数 ---
_get_ip_address() {
	local ver="$1"
	local iface_override="$2"
	local ip=""
	local ip_cmd="ip -$ver"

	local match_pattern="inet"
	[ "$ver" = "6" ] && match_pattern="inet6"

	if [ -n "$iface_override" ]; then
		ip=$($ip_cmd addr show dev "$iface_override" 2>/dev/null | awk -v v="$match_pattern" '$1 ~ v {print $2}' | cut -d'/' -f1 | head -n1)
	fi

	if [ -z "$ip" ]; then
		local default_iface
		default_iface=$($ip_cmd route show default 2>/dev/null | awk '{print $5}' | head -n1)
		if [ -n "$default_iface" ]; then
			ip=$($ip_cmd addr show dev "$default_iface" 2>/dev/null | awk -v v="$match_pattern" '$1 ~ v {print $2}' | cut -d'/' -f1 | head -n1)
		fi
	fi

	if [ -z "$ip" ]; then
		if [ "$ver" = "4" ]; then
			ip=$(hostname -I 2>/dev/null | awk '{print $1}')
		else
			ip=$($ip_cmd addr show 2>/dev/null | awk -v v="$match_pattern" '/scope global/ && $2 !~ /^fe80:/ {print $2}' | cut -d'/' -f1 | head -n1)
		fi
	fi

	if [ -z "$ip" ]; then
		if [ "$ver" = "4" ] && command -v curl >/dev/null 2>&1; then
			ip=$(timeout 3s curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)
		elif [ "$ver" = "6" ] && command -v curl >/dev/null 2>&1; then
			ip=$(timeout 3s curl -6 -fsSL https://api64.ipify.org 2>/dev/null || true)
		fi
	fi

	echo "${ip:-N/A}"
}

# --- 辅助工具函数 ---
_print_header() { echo -e "\n${BLUE}--- ${1} ---${NC}"; }
_format_seconds_to_human() {
	local total_seconds="$1"
	if ! [[ "$total_seconds" =~ ^[0-9]+$ ]] || [ "$total_seconds" -le 0 ]; then
		echo "N/A"
		return
	fi
	local days=$((total_seconds / 86400))
	local hours=$(((total_seconds % 86400) / 3600))
	local minutes=$(((total_seconds % 3600) / 60))
	local seconds=$((total_seconds % 60))
	local result=""
	[ "$days" -gt 0 ] && result+="${days}天"
	[ "$hours" -gt 0 ] && result+="${hours}小时"
	[ "$minutes" -gt 0 ] && result+="${minutes}分钟"
	[ "$seconds" -gt 0 ] && result+="${seconds}秒"
	echo "${result:-0秒}"
}

_mask_ip() {
	local ip="${1:-}"
	if [ -z "$ip" ] || [ "$ip" = "N/A" ]; then
		printf '%s\n' "N/A"
		return 0
	fi
	if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		IFS='.' read -r a b _c _d <<<"$ip"
		printf '%s\n' "${a}.${b}.*.*"
	elif [[ "$ip" =~ .*:.* ]]; then
		IFS=':' read -r a b _rest <<<"$ip"
		printf '%s\n' "${a}:${b}::***"
	else
		printf '%s\n' "***"
	fi
}
_escape_markdown() {
	local input="${1:-}"
	if [ -z "$input" ]; then
		echo ""
		return
	fi
	# shellcheck disable=SC2016
	echo "$input" | sed 's/_/\\_/g; s/\*/\\*/g; s/`/\\`/g; s/\[/\\[/g'
}

_get_watchtower_local_image_info() {
	local image="${1:-}"
	if [ -z "$image" ]; then return 1; fi
	local info=""
	info=$(JB_SUDO_LOG_QUIET="true" run_with_sudo docker image inspect "$image" --format '{{.Id}}|{{.Created}}' 2>/dev/null || true)
	if [ -z "$info" ]; then return 1; fi
	local image_id=""
	local created=""
	local short_id=""
	image_id=${info%%|*}
	created=${info#*|}
	short_id=${image_id#sha256:}
	short_id=${short_id:0:12}
	printf '%s' "本地镜像: ${image} (${short_id:-unknown}, created=${created:-unknown})"
}

_log_watchtower_pull_failure() {
	local image="${1:-}"
	local local_info=""
	if local_info=$(_get_watchtower_local_image_info "$image"); then
		log_warn "镜像拉取失败，继续使用本地镜像（可能较旧）。${local_info}"
		return 0
	fi
	log_warn "镜像拉取失败，且本地未找到可用镜像。"
	return 1
}

_watchtower_is_running() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker ps --format "${WATCHTOWER_DOCKER_NAMES_FORMAT}" | grep -qFx "${WATCHTOWER_CONTAINER_NAME}"
}

_watchtower_exists() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker ps -a --format "${WATCHTOWER_DOCKER_NAMES_FORMAT}" | grep -qFx "${WATCHTOWER_CONTAINER_NAME}"
}

_watchtower_inspect_env() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker inspect "${WATCHTOWER_CONTAINER_NAME}" --format "${WATCHTOWER_INSPECT_ENV_FORMAT}"
}

_watchtower_inspect_cmd() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker inspect "${WATCHTOWER_CONTAINER_NAME}" --format "${WATCHTOWER_INSPECT_CMD_FORMAT}"
}

_watchtower_inspect_created() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker inspect --format "${WATCHTOWER_INSPECT_CREATED_FORMAT}" "${WATCHTOWER_CONTAINER_NAME}"
}

_watchtower_logs_tail() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker logs --tail 500 "${WATCHTOWER_CONTAINER_NAME}"
}

_watchtower_logs_follow() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker logs -f --tail 100 "${WATCHTOWER_CONTAINER_NAME}"
}

_remove_watchtower_container() {
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker rm -f "${WATCHTOWER_CONTAINER_NAME}" &>/dev/null || true
}

_remove_named_watchtower_container() {
	local container_name="${1:-}"
	[ -n "$container_name" ] || return 0
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker rm -f "$container_name" &>/dev/null || true
}

_rename_watchtower_container() {
	local from_name="${1:-}"
	local to_name="${2:-}"
	[ -n "$from_name" ] && [ -n "$to_name" ] || return 1
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker rename "$from_name" "$to_name"
}

_stable_watchtower_env_hash() {
	local source_file="${1:-}"
	[ -f "$source_file" ] || return 1
	grep -v '^WATCHTOWER_NOTIFICATION_TEMPLATE=' "$source_file" 2>/dev/null | md5sum | awk '{print $1}'
}

_select_watchtower_image() {
	local primary="${1:-}"
	local fallback="${2:-}"
	local allow_local_fallback="${3:-true}"
	local selected="$primary"
	if [ -z "$primary" ]; then return 1; fi
	if JB_SUDO_LOG_QUIET="true" run_with_sudo docker pull "$primary" >/dev/null 2>&1; then
		printf '%s' "$selected"
		return 0
	fi

	log_warn "主镜像拉取失败，尝试回退镜像仓库..."
	if [ -n "$fallback" ] && JB_SUDO_LOG_QUIET="true" run_with_sudo docker pull "$fallback" >/dev/null 2>&1; then
		selected="$fallback"
		log_info "已回退使用 Docker Hub 镜像: ${fallback}"
		printf '%s' "$selected"
		return 0
	fi

	if [ "$allow_local_fallback" != "true" ]; then
		log_warn "镜像拉取失败，且已禁用本地旧镜像回退。"
		return 1
	fi

	local primary_info=""
	local fallback_info=""
	primary_info=$(_get_watchtower_local_image_info "$primary" || true)
	fallback_info=$(_get_watchtower_local_image_info "$fallback" || true)
	if [ -n "$primary_info" ]; then
		log_warn "镜像拉取失败，继续使用本地镜像（可能较旧）。${primary_info}"
		printf '%s' "$selected"
		return 0
	fi
	if [ -n "$fallback_info" ]; then
		log_warn "镜像拉取失败，继续使用本地镜像（可能较旧）。${fallback_info}"
		selected="$fallback"
		printf '%s' "$selected"
		return 0
	fi

	log_warn "镜像拉取失败，且本地未找到可用镜像。"
	return 1
}

_build_watchtower_image_ref() {
	local repo="${1:-}"
	local tag="${2:-latest}"
	if [ -z "$repo" ] || [ -z "$tag" ]; then
		return 1
	fi
	printf '%s:%s' "$repo" "$tag"
}

_trim_shell_whitespace() {
	local value="${1:-}"
	value=$(printf '%s' "$value" | tr -d '\r\n')
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

_detect_docker_server_api_version() {
	if ! command -v docker &>/dev/null; then
		return 1
	fi

	local detected=""
	detected=$(JB_SUDO_LOG_QUIET="true" run_with_sudo docker version --format '{{.Server.MinAPIVersion}}' 2>/dev/null || true)
	detected=$(_trim_shell_whitespace "$detected")

	if [ -z "$detected" ] || [ "$detected" = "<no value>" ] || [ "$detected" = "<nil>" ]; then
		detected=$(JB_SUDO_LOG_QUIET="true" run_with_sudo docker version --format '{{.Server.APIVersion}}' 2>/dev/null || true)
		detected=$(_trim_shell_whitespace "$detected")
	fi

	if [ -z "$detected" ] || [ "$detected" = "<no value>" ] || [ "$detected" = "<nil>" ]; then
		return 1
	fi

	printf '%s' "$detected"
}

_resolve_watchtower_docker_api_version() {
	local configured="${WATCHTOWER_DOCKER_API_VERSION:-}"
	configured=$(printf '%s' "$configured" | tr -d '\n\r[:space:]')
	if [ -n "$configured" ]; then
		printf '%s' "$configured"
		return 0
	fi

	_detect_docker_server_api_version
}

_resolve_watchtower_image() {
	local primary_repo="${WATCHTOWER_IMAGE_PRIMARY_REPO:-ghcr.io/containrrr/watchtower}"
	local fallback_repo="${WATCHTOWER_IMAGE_FALLBACK_REPO:-containrrr/watchtower}"
	local tag="${WATCHTOWER_IMAGE_TAG:-latest}"
	local allow_local_fallback="${WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK:-true}"
	local primary_image=""
	local fallback_image=""

	primary_image=$(_build_watchtower_image_ref "$primary_repo" "$tag" || true)
	if [ -z "$primary_image" ]; then
		log_error "Watchtower 主镜像配置无效，请检查镜像仓库或标签。"
		return 1
	fi

	if [ -n "$fallback_repo" ]; then
		fallback_image=$(_build_watchtower_image_ref "$fallback_repo" "$tag" || true)
	fi

	_select_watchtower_image "$primary_image" "$fallback_image" "$allow_local_fallback"
}

# --- 通知发送函数 ---
send_test_notify() {
	local message="$1"
	if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
		log_warn "Telegram 配置不完整，跳过通知。"
		return "${ERR_CONFIG}"
	fi
	if ! command -v jq &>/dev/null; then
		log_error "缺少 jq，无法发送测试通知。"
		return "${ERR_DEPENDENCY}"
	fi
	local url="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
	local data
	data=$(jq -n --arg chat_id "$TG_CHAT_ID" --arg text "$message" '{chat_id: $chat_id, text: $text, parse_mode: "Markdown"}')

	local curl_result
	curl_result=$(timeout 10s curl -s -w "\n%{http_code}" -X POST -H 'Content-Type: application/json' -d "$data" "$url" 2>&1) || {
		log_error "curl 执行失败或超时: $curl_result"
		return "${ERR_RUNTIME}"
	}

	local http_code
	http_code=$(echo "$curl_result" | tail -n1)
	local body
	body=$(echo "$curl_result" | sed '$d')

	if [ "$http_code" != "200" ]; then
		log_error "Telegram API 返回错误 (HTTP $http_code): $body"
		return "${ERR_RUNTIME}"
	fi

	log_success "通知发送成功！"
	return "${ERR_OK}"
}

_prompt_for_interval() {
	local default_interval_seconds="$1"
	local prompt_message="$2"
	local input_value
	local current_display_value
	current_display_value="$(_format_seconds_to_human "$default_interval_seconds")"
	while true; do
		input_value=$(_prompt_user_input "${prompt_message} (例如: 3600, 1h, 30m, 1d, 当前: ${current_display_value}): " "")
		if [ -z "$input_value" ]; then
			echo "$default_interval_seconds"
			return "${ERR_OK}"
		fi
		local seconds=0
		if [[ "$input_value" =~ ^[0-9]+$ ]]; then
			seconds="$input_value"
		elif [[ "$input_value" =~ ^([0-9]+)s$ ]]; then
			seconds="${BASH_REMATCH[1]}"
		elif [[ "$input_value" =~ ^([0-9]+)m$ ]]; then
			seconds=$(("${BASH_REMATCH[1]}" * 60))
		elif [[ "$input_value" =~ ^([0-9]+)h$ ]]; then
			seconds=$(("${BASH_REMATCH[1]}" * 3600))
		elif [[ "$input_value" =~ ^([0-9]+)d$ ]]; then
			seconds=$(("${BASH_REMATCH[1]}" * 86400))
		else
			log_warn "无效格式。"
			continue
		fi
		if [ "$seconds" -gt 0 ]; then
			echo "$seconds"
			return "${ERR_OK}"
		else log_warn "间隔必须是正数。"; fi
	done
}

_parse_watchtower_extra_args() {
	local raw_args="${WATCHTOWER_EXTRA_ARGS:-}"
	[ -z "$raw_args" ] && return 0

	local sanitized_args
	sanitized_args=$(_sanitize_input_text "$raw_args")
	if [ "$sanitized_args" != "$raw_args" ]; then
		log_error "额外参数包含非法控制字符，请检查配置。"
		return "${ERR_CONFIG}"
	fi

	local extra_tokens=()
	local old_ifs="${IFS:-}"
	IFS=' '
	read -r -a extra_tokens <<<"$raw_args"
	IFS="$old_ifs"

	local token
	for token in "${extra_tokens[@]}"; do
		if [[ ! "$token" =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]]; then
			log_error "额外参数包含不受支持的 token: $token"
			return "${ERR_CONFIG}"
		fi
		case "$token" in
		--run-once | --cleanup | --debug | --interval | --interval=* | --schedule | --schedule=*)
			log_error "额外参数禁止覆盖封装器已管理的选项: $token"
			return "${ERR_CONFIG}"
			;;
		esac
		printf '%s\n' "$token"
	done
	return 0
}

# --- 核心：生成环境文件 ---
_generate_env_file() {
	local target_file="${1:-$ENV_FILE}"
	local alias_name
	alias_name=$(echo "${WATCHTOWER_HOST_ALIAS:-DockerNode}" | tr -d '\n\r')
	local alias_masked
	alias_masked=$(_mask_string "$alias_name" 2)

	local ipv4_address ipv6_address
	ipv4_address=$(_get_ip_address 4 "${WATCHTOWER_IPV4_INTERFACE}")
	ipv6_address=$(_get_ip_address 6 "${WATCHTOWER_IPV6_INTERFACE}")
	local ipv4_masked ipv6_masked
	ipv4_masked=$(_mask_ip "$ipv4_address")
	ipv6_masked=$(_mask_ip "$ipv6_address")
	local resolved_api_version=""
	resolved_api_version=$(_resolve_watchtower_docker_api_version 2>/dev/null || true)

	rm -f "$target_file"

	{
		echo "TZ=${JB_TIMEZONE:-Asia/Shanghai}"
		echo "JB_WATCHTOWER_HOST_ALIAS=${WATCHTOWER_HOST_ALIAS:-DockerNode}"
		echo "JB_WATCHTOWER_IPV4_INTERFACE=${WATCHTOWER_IPV4_INTERFACE:-}"
		echo "JB_WATCHTOWER_IPV6_INTERFACE=${WATCHTOWER_IPV6_INTERFACE:-}"
		if [ -n "$resolved_api_version" ]; then
			echo "DOCKER_API_VERSION=${resolved_api_version}"
		else
			log_warn "未解析到 Docker API 版本，将使用 Watchtower 容器默认行为。"
		fi

		if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
			echo "WATCHTOWER_NOTIFICATIONS=shoutrrr"
			echo "WATCHTOWER_NOTIFICATION_URL=telegram://${TG_BOT_TOKEN}@telegram?parsemode=Markdown&preview=false&channels=${TG_CHAT_ID}"
			echo "WATCHTOWER_NO_STARTUP_MESSAGE=true"
			echo "WATCHTOWER_NOTIFICATION_REPORT=${WATCHTOWER_NOTIFY_ON_NO_UPDATES:-${WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES}}"

			local br='{{ "\n" }}'
			local template_time
			template_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"

			if [ "${WATCHTOWER_NOTIFY_ON_NO_UPDATES:-${WATCHTOWER_DEFAULT_NOTIFY_ON_NO_UPDATES}}" = "true" ]; then
				cat <<EOF | tr -d '\n' >>"$target_file"
WATCHTOWER_NOTIFICATION_TEMPLATE={{- with .Report }}✅ *容器自动更新通知*${br}${br}🖥️ *主机:* \`${alias_masked}\`${br}🌐 *IPv4:* \`${ipv4_masked}\`${br}🌐 *IPv6:* \`${ipv6_masked}\`${br}⌚ *时间:* \`${template_time}\`${br}${br}📄 *状态:* 已扫描 \`{{ len .Scanned }}\`，更新 \`{{ len .Updated }}\`，失败 \`{{ len .Failed }}\`${br}🧹 *清理状态:* {{- if gt (len .Failed) 0 }}\`需人工检查（存在更新失败）\`{{- else }}\`已执行（--cleanup）\`{{- end }}{{- if .Updated }}${br}${br}🧾 *更新详情:*${br}{{- range .Updated }}• \`{{ .Name }}\` 从 \`{{ .CurrentImageID.ShortID }}\` 更新到 \`{{ .LatestImageID.ShortID }}\`${br}{{- end }}{{- end }}{{- if .Failed }}${br}${br}❌ *失败详情:*${br}{{- range .Failed }}• \`{{ .Name }}\` : {{ .Error }}${br}{{- end }}{{- end }}{{- end }}
EOF
			else
				cat <<EOF | tr -d '\n' >>"$target_file"
WATCHTOWER_NOTIFICATION_TEMPLATE={{- with .Report }}{{- if or (gt (len .Updated) 0) (gt (len .Failed) 0) }}✅ *容器自动更新通知*${br}${br}🖥️ *主机:* \`${alias_masked}\`${br}🌐 *IPv4:* \`${ipv4_masked}\`${br}🌐 *IPv6:* \`${ipv6_masked}\`${br}⌚ *时间:* \`${template_time}\`${br}${br}📄 *状态:* 已扫描 \`{{ len .Scanned }}\`，更新 \`{{ len .Updated }}\`，失败 \`{{ len .Failed }}\`${br}🧹 *清理状态:* {{- if gt (len .Failed) 0 }}\`需人工检查（存在更新失败）\`{{- else }}\`已执行（--cleanup）\`{{- end }}${br}{{- if .Updated }}${br}🧾 *更新详情:*${br}{{- range .Updated }}• \`{{ .Name }}\` 从 \`{{ .CurrentImageID.ShortID }}\` 更新到 \`{{ .LatestImageID.ShortID }}\`${br}{{- end }}{{- end }}{{- if .Failed }}${br}❌ *失败详情:*${br}{{- range .Failed }}• \`{{ .Name }}\` : {{ .Error }}${br}{{- end }}{{- end }}{{- end }}{{- end }}
EOF
			fi
			printf '\n' >>"$target_file"
		fi

		if [[ "$WATCHTOWER_RUN_MODE" == "cron" || "$WATCHTOWER_RUN_MODE" == "aligned" ]] && [ -n "$WATCHTOWER_SCHEDULE_CRON" ]; then
			if ! _validate_watchtower_cron_expression "$WATCHTOWER_SCHEDULE_CRON"; then
				log_error "Watchtower Cron 配置无效: $WATCHTOWER_SCHEDULE_CRON"
				return "${ERR_CONFIG}"
			fi
			echo "WATCHTOWER_SCHEDULE=$WATCHTOWER_SCHEDULE_CRON"
		fi
	} >>"$target_file"

	if grep -qE 'WATCHTOWER_NOTIFICATION_TEMPLATE=.*WATCHTOWER_[A-Z_]+' "$target_file" 2>/dev/null; then
		log_error "通知模板写入异常：检测到环境变量被拼接到模板同一行，请重试。"
		return "${ERR_CONFIG}"
	fi

	chmod 600 "$target_file" || log_warn "⚠️ 无法设置环境文件权限。"
}

# --- 健康检查与核心启动逻辑 ---
_wait_for_container_healthy() {
	local container_name="$1"
	local timeout=30
	local interval=5
	local end_time=$(($(date +%s) + timeout))

	log_info "执行启动后健康检查 (超时: ${timeout}s)..."
	while [ "$(date +%s)" -lt "$end_time" ]; do
		local status
		status=$(JB_SUDO_LOG_QUIET="true" run_with_sudo docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not-found")

		case "$status" in
		"running")
			log_success "容器 '$container_name' 已成功启动并处于运行状态。"
			return "${ERR_OK}"
			;;
		"exited" | "dead")
			log_error "容器 '$container_name' 启动失败，状态为 '$status'。请检查日志。"
			JB_SUDO_LOG_QUIET="true" run_with_sudo docker logs "$container_name" >&2
			return "${ERR_RUNTIME}"
			;;
		"not-found")
			log_error "容器 '$container_name' 未找到，启动命令可能已失败。"
			return "${ERR_RUNTIME}"
			;;
		*)
			log_info "容器状态: '$status'，等待中..."
			sleep "$interval"
			;;
		esac
	done

	log_error "健康检查超时！容器 '$container_name' 在 ${timeout} 秒内未能进入 'running' 状态。"
	return "${ERR_RUNTIME}"
}

prune_dangling_images() {
	log_info "清理悬挂镜像 (docker image prune -f)..."
	if JB_SUDO_LOG_QUIET="true" run_with_sudo docker image prune -f >/dev/null 2>&1; then
		log_success "悬挂镜像清理完成。"
		return "${ERR_OK}"
	fi
	log_warn "悬挂镜像清理失败或被跳过。"
	return "${ERR_RUNTIME}"
}

_start_watchtower_container_logic() {
	load_config
	local wt_interval="$1"
	local mode_description="$2"
	local interactive_mode="${3:-false}"
	local wt_image=""
	local container_names=()
	local run_hostname="${WATCHTOWER_HOST_ALIAS:-DockerNode}"
	_generate_env_file "$ENV_FILE"
	local docker_run_args=(-h "${run_hostname}")
	docker_run_args+=(--env-file "$ENV_FILE")
	local wt_args=("--cleanup")
	local run_container_name="watchtower"
	if [ "$interactive_mode" = "true" ]; then
		run_container_name="watchtower-once"
		docker_run_args+=(--rm --name "$run_container_name")
		wt_args+=(--run-once)
	else
		docker_run_args+=(-d --name "$run_container_name" --restart unless-stopped)
		if [[ "$WATCHTOWER_RUN_MODE" != "cron" && "$WATCHTOWER_RUN_MODE" != "aligned" ]]; then
			log_info "⏳ 启用间隔循环模式: ${wt_interval:-300}秒"
			wt_args+=(--interval "${wt_interval:-300}")
		else log_info "⏰ 启用 Cron 调度模式: $WATCHTOWER_SCHEDULE_CRON"; fi
	fi
	docker_run_args+=(-v /var/run/docker.sock:/var/run/docker.sock)
	[ "$WATCHTOWER_DEBUG_ENABLED" = "true" ] && wt_args+=("--debug")
	if [[ "$WATCHTOWER_RUN_MODE" == "cron" || "$WATCHTOWER_RUN_MODE" == "aligned" ]] && [ -n "$WATCHTOWER_SCHEDULE_CRON" ]; then
		if ! _validate_watchtower_cron_expression "$WATCHTOWER_SCHEDULE_CRON"; then
			log_error "Watchtower Cron 配置无效: $WATCHTOWER_SCHEDULE_CRON"
			return "${ERR_CONFIG}"
		fi
	fi
	if [ -n "$WATCHTOWER_EXTRA_ARGS" ]; then
		local parsed_extra_tokens=()
		if ! mapfile -t parsed_extra_tokens < <(_parse_watchtower_extra_args); then
			return "${ERR_CONFIG}"
		fi
		wt_args+=("${parsed_extra_tokens[@]}")
	fi
	local final_exclude_list="${WATCHTOWER_EXCLUDE_LIST}"
	if [ -n "$final_exclude_list" ]; then
		local -A excluded_map=()
		local old_ifs="${IFS:-}"
		local excluded_item=""
		excluded_map["watchtower"]=1
		excluded_map["watchtower-once"]=1
		IFS=','
		read -r -a _excluded_items <<<"$final_exclude_list"
		IFS="$old_ifs"
		while IFS= read -r excluded_item; do
			excluded_item=$(printf '%s' "$excluded_item" | xargs)
			[ -n "$excluded_item" ] && excluded_map["$excluded_item"]=1
		done < <(printf '%s\n' "${_excluded_items[@]}")
		while IFS= read -r container_name; do
			[ -z "$container_name" ] && continue
			if [ -n "${excluded_map[$container_name]+_}" ]; then
				continue
			fi
			container_names+=("$container_name")
		done < <(JB_SUDO_LOG_QUIET="true" run_with_sudo docker ps --format '{{.Names}}' 2>/dev/null || true)
		if [ ${#container_names[@]} -eq 0 ] && [ "$interactive_mode" = "false" ]; then
			log_error "忽略名单导致监控范围为空，服务无法启动。"
			return "${ERR_CONFIG}"
		fi
		[ "$interactive_mode" = "false" ] && log_info "计算后的监控范围: ${container_names[*]}"
	else [ "$interactive_mode" = "false" ] && log_info "未发现忽略名单，将监控所有容器。"; fi
	if [ "$interactive_mode" = "false" ]; then echo "⬇️ 正在拉取 Watchtower 镜像..."; fi
	wt_image=$(_resolve_watchtower_image || true)
	if [ -z "$wt_image" ]; then
		log_error "镜像拉取失败，且本地未找到可用镜像。"
		return "${ERR_RUNTIME}"
	fi
	[ "$interactive_mode" = "false" ] && log_info "Watchtower 镜像已解析为: ${wt_image}"
	[ "$interactive_mode" = "false" ] && _print_header "正在启动 $mode_description"

	local final_command_to_run=(docker run "${docker_run_args[@]}" "$wt_image" "${wt_args[@]}" "${container_names[@]}")

	if [ "$interactive_mode" = "true" ]; then
		log_info "正在执行立即更新扫描..."
		JB_SUDO_LOG_QUIET="true" run_with_sudo "${final_command_to_run[@]}" || {
			log_error "手动扫描执行失败"
			return "${ERR_RUNTIME}"
		}
		prune_dangling_images || true
		log_success "手动更新扫描任务已结束"
		return "${ERR_OK}"
	else
		[ "$interactive_mode" = "false" ] && echo -e "${CYAN}执行命令: JB_SUDO_LOG_QUIET=true run_with_sudo docker run ...${NC}"

		local rc=0
		JB_SUDO_LOG_QUIET="true" run_with_sudo "${final_command_to_run[@]}" || rc=$?

		if [ "$rc" -ne 0 ]; then
			log_error "$mode_description 启动命令失败 (exit code: $rc)"
			return "${ERR_RUNTIME}"
		fi

		if ! _wait_for_container_healthy "$run_container_name"; then
			log_error "自修复：启动失败，正在清理残留的 '$run_container_name' 容器..."
			JB_SUDO_LOG_QUIET="true" run_with_sudo docker rm -f "$run_container_name" &>/dev/null || true
			return "${ERR_RUNTIME}"
		fi

		cp -f "$ENV_FILE" "$ENV_FILE_LAST_RUN"
		return "${ERR_OK}"
	fi
}

_rebuild_watchtower() {
	log_info "正在重建 Watchtower 容器..."
	local interval="${WATCHTOWER_CONFIG_INTERVAL}"
	local backup_container_name="${WATCHTOWER_BACKUP_CONTAINER_NAME}"
	local had_existing_container="false"

	if _watchtower_exists; then
		had_existing_container="true"
		_remove_named_watchtower_container "$backup_container_name"
		if ! _rename_watchtower_container "${WATCHTOWER_CONTAINER_NAME}" "$backup_container_name"; then
			log_error "无法为现有 Watchtower 容器创建重建保护备份。"
			return "${ERR_RUNTIME}"
		fi
	fi

	if ! _start_watchtower_container_logic "$interval" "Watchtower (监控模式)"; then
		log_error "Watchtower 重建失败！"
		if [ "$had_existing_container" = "true" ]; then
			_remove_named_watchtower_container "${WATCHTOWER_CONTAINER_NAME}"
			if _rename_watchtower_container "$backup_container_name" "${WATCHTOWER_CONTAINER_NAME}"; then
				log_warn "已恢复重建前的 Watchtower 容器。"
			else
				log_error "旧 Watchtower 容器恢复失败，请手动检查 Docker 容器状态。"
			fi
		fi
		return "${ERR_RUNTIME}"
	fi

	if [ "$had_existing_container" = "true" ]; then
		_remove_named_watchtower_container "$backup_container_name"
	fi

	prune_dangling_images || true

	log_success "Watchtower 重建成功！"
	return "${ERR_OK}"
}

_prompt_rebuild_if_needed() {
	if [ "${JB_NONINTERACTIVE:-false}" = "true" ]; then
		return
	fi

	if ! _watchtower_is_running; then return; fi
	if [ ! -f "$ENV_FILE_LAST_RUN" ]; then return; fi

	local temp_env
	temp_env=$(mktemp)
	TEMP_FILES+=("$temp_env")

	if ! _generate_env_file "$temp_env" 2>/dev/null; then
		log_warn "无法生成最新 Watchtower 环境快照，已跳过重建提示检查。"
		return
	fi

	local current_hash new_hash
	current_hash=$(_stable_watchtower_env_hash "$ENV_FILE_LAST_RUN" 2>/dev/null || true)
	new_hash=$(_stable_watchtower_env_hash "$temp_env" 2>/dev/null || true)
	if [ -z "$current_hash" ] || [ -z "$new_hash" ]; then
		log_warn "无法比较 Watchtower 配置快照，已跳过重建提示检查。"
		return
	fi

	if [ "$current_hash" != "$new_hash" ]; then
		echo -e "\n${RED}⚠️ 检测到配置已变更 (Diff Found)，建议前往'服务运维'重建服务以生效。${NC}"
		if confirm_action "检测到配置变更，是否立即重建 Watchtower 以应用新配置?"; then
			_rebuild_watchtower || return $?
		fi
	fi
}

run_watchtower_once() {
	local skip_confirm="${1:-false}"
	local before_mode before_interval before_cron
	before_mode="${WATCHTOWER_RUN_MODE:-}"
	before_interval="${WATCHTOWER_CONFIG_INTERVAL:-}"
	before_cron="${WATCHTOWER_SCHEDULE_CRON:-}"

	if [ "$skip_confirm" != "true" ] && ! confirm_action "确定要运行一次 Watchtower 来更新所有容器吗?"; then
		log_info "操作已取消。"
		return "${ERR_OK}"
	fi
	if ! _start_watchtower_container_logic "" "" true; then
		return "${ERR_RUNTIME}"
	fi

	if [ "${WATCHTOWER_RUN_MODE:-}" != "$before_mode" ] || [ "${WATCHTOWER_CONFIG_INTERVAL:-}" != "$before_interval" ] || [ "${WATCHTOWER_SCHEDULE_CRON:-}" != "$before_cron" ]; then
		WATCHTOWER_RUN_MODE="$before_mode"
		WATCHTOWER_CONFIG_INTERVAL="$before_interval"
		WATCHTOWER_SCHEDULE_CRON="$before_cron"
		log_warn "检测到手动扫描期间调度参数被改动，已自动恢复。"
	fi

	return "${ERR_OK}"
}

# --- 菜单函数 ---
_configure_telegram() {
	local old_token="${TG_BOT_TOKEN}"
	local old_chat_id="${TG_CHAT_ID}"
	local masked_token="[未设置]"
	local masked_chat_id="[未设置]"

	if [ -n "$TG_BOT_TOKEN" ]; then
		masked_token=$(_mask_string "$TG_BOT_TOKEN" 8)
	fi
	if [ -n "$TG_CHAT_ID" ]; then
		masked_chat_id=$(_mask_string "$TG_CHAT_ID" 6)
	fi

	echo -e "当前 Token: ${GREEN}${masked_token}${NC}"
	local val
	read -r -p "请输入 Telegram Bot Token (回车保持, 空格清空): " val
	val="$(_sanitize_input_text "$val")"
	if [[ "$val" =~ ^[[:space:]]+$ ]]; then
		TG_BOT_TOKEN=""
		log_info "Token 已清空。"
	elif [ -n "$val" ]; then
		TG_BOT_TOKEN="$val"
	fi

	echo -e "当前 Chat ID: ${GREEN}${masked_chat_id}${NC}"
	read -r -p "请输入 Chat ID (回车保持, 空格清空): " val
	val="$(_sanitize_input_text "$val")"
	if [[ "$val" =~ ^[[:space:]]+$ ]]; then
		TG_CHAT_ID=""
		log_info "Chat ID 已清空。"
	elif [ -n "$val" ]; then
		TG_CHAT_ID="$val"
	fi

	if [ "$old_token" = "$TG_BOT_TOKEN" ] && [ "$old_chat_id" = "$TG_CHAT_ID" ]; then
		log_info "配置未变更，跳过保存与重建提示。"
		return 0
	fi

	save_config
	log_info "通知配置已保存。"
	_prompt_rebuild_if_needed
}

_configure_encryption() {
	if ! command -v openssl &>/dev/null; then
		log_error "此功能需要 openssl，请先安装。"
		return
	fi
	local choice
	choice=$(_prompt_user_input "是否启用配置加密? (y/N, 当前: ${CONFIG_ENCRYPTED}): " "")
	if echo "$choice" | grep -qE '^[Yy]$'; then
		if [ "$CONFIG_ENCRYPTED" = "true" ]; then
			log_info "加密已启用。"
			return
		fi
		log_info "即将启用加密。您需要设置一个主密码。"
		read -r -s -p "请输入新密码: " pass1
		echo
		read -r -s -p "请再次输入密码确认: " pass2
		echo
		if [ "$pass1" != "$pass2" ] || [ -z "$pass1" ]; then
			log_error "密码不匹配或为空！操作取消。"
			return
		fi
		SESSION_ENCRYPTION_PASSWORD="$pass1"
		CONFIG_ENCRYPTED="true"
		log_success "加密已启用！正在保存配置..."
	else
		if [ "$CONFIG_ENCRYPTED" = "false" ]; then
			log_info "加密已禁用。"
			return
		fi
		CONFIG_ENCRYPTED="false"
		SESSION_ENCRYPTION_PASSWORD=""
		log_success "加密已禁用。令牌将以明文形式保存。"
	fi
	save_config
}

_configure_alias() {
	echo -e "当前别名: ${GREEN}${WATCHTOWER_HOST_ALIAS:-DockerNode}${NC}"
	local val
	read -r -p "设置服务器别名 (回车保持, 空格恢复默认): " val
	if [[ "$val" =~ ^\ +$ ]]; then
		WATCHTOWER_HOST_ALIAS="DockerNode"
		log_info "已恢复默认别名。"
	elif [ -n "$val" ]; then
		WATCHTOWER_HOST_ALIAS="$val"
	fi
	save_config
	log_info "服务器别名已设置为: $WATCHTOWER_HOST_ALIAS"
	_prompt_rebuild_if_needed
}

notification_menu() {
	while true; do
		if should_clear_screen "watchtower:notification_menu"; then clear; fi

		local tg_status="${RED}未配置${NC}"
		if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
			tg_status="${GREEN}已配置${NC}"
		fi

		local alias_status="${CYAN}${WATCHTOWER_HOST_ALIAS:-默认}${NC}"
		local crypto_status="${RED}禁用${NC}"
		[ "$CONFIG_ENCRYPTED" = "true" ] && crypto_status="${GREEN}启用${NC}"

		local -a content_array=(
			"1. 配置 Telegram (状态: $tg_status)"
			"2. 设置服务器别名 (当前: $alias_status)"
			"3. 启用/禁用配置加密 (当前: $crypto_status)"
			"4. 发送手动测试通知"
			"5. 清空所有通知配置"
		)
		_render_menu "⚙️ 通知配置 ⚙️" "${content_array[@]}"

		local choice
		choice=$(_prompt_for_menu_choice "1-5")
		case "$choice" in
		1)
			_configure_telegram
			press_enter_to_continue
			;;
		2)
			_configure_alias
			press_enter_to_continue
			;;
		3)
			_configure_encryption
			press_enter_to_continue
			;;
		4)
			if [ -z "$TG_BOT_TOKEN" ]; then
				log_warn "请先配置 Telegram。"
			else
				log_info "正在发送测试通知..."
				send_test_notify "*🔔 手动测试消息*
来自 Docker 助手 \`$(_escape_markdown "$SCRIPT_VERSION")\` 的测试。
*状态:* ✅ 成功连接"
			fi
			press_enter_to_continue
			;;
		5)
			if confirm_action "确定要清空所有通知配置吗?"; then
				TG_BOT_TOKEN=""
				TG_CHAT_ID=""
				save_config
				log_info "已清空。"
				_prompt_rebuild_if_needed
			else log_info "已取消。"; fi
			press_enter_to_continue
			;;
		"") return ;;
		*)
			log_warn "无效选项。"
			sleep 1
			;;
		esac
	done
}

_configure_schedule() {
	local valid_choice=false
	local mode_choice=""

	while [ "$valid_choice" = "false" ]; do
		echo -e "${CYAN}请选择运行模式:${NC}"
		echo "1. 间隔循环 (每隔 X 小时/分钟，可选择对齐整点)"
		echo "2. 自定义 Cron 表达式 (高级)"

		mode_choice=$(_prompt_for_menu_choice "1-2")

		if [ "$mode_choice" = "1" ] || [ "$mode_choice" = "2" ]; then
			valid_choice=true
		else
			log_warn "无效选项，请输入 1 或 2。"
		fi
	done

	if [ "$mode_choice" = "1" ]; then
		local interval_hour=""
		while true; do
			interval_hour=$(_prompt_user_input "每隔几小时运行一次? (输入 0 表示使用分钟): " "")
			if [[ "$interval_hour" =~ ^[0-9]+$ ]]; then break; fi
			log_warn "请输入数字。"
		done
		if [ "$interval_hour" -gt 0 ]; then
			echo -e "${CYAN}请选择对齐方式:${NC}"
			echo "1. 从现在开始计时 (容器启动时间 + 间隔)"
			echo "2. 对齐到整点 (:00)"
			echo "3. 对齐到半点 (:30)"
			local align_choice
			align_choice=$(_prompt_for_menu_choice "1-3")
			if [ "$align_choice" = "1" ]; then
				WATCHTOWER_RUN_MODE="interval"
				WATCHTOWER_CONFIG_INTERVAL=$((interval_hour * 3600))
				WATCHTOWER_SCHEDULE_CRON=""
				log_info "已设置: 每 $interval_hour 小时运行一次 (立即生效)"
			else
				WATCHTOWER_RUN_MODE="aligned"
				local minute="0"
				[ "$align_choice" = "3" ] && minute="30"
				WATCHTOWER_SCHEDULE_CRON="0 $minute */$interval_hour * * *"
				log_info "已设置: 每 $interval_hour 小时在 :$minute 运行 (Cron: $WATCHTOWER_SCHEDULE_CRON)"
				WATCHTOWER_CONFIG_INTERVAL="0"
			fi
		else
			WATCHTOWER_RUN_MODE="interval"
			local min_val
			min_val=$(_prompt_for_interval "300" "请输入运行频率")
			WATCHTOWER_CONFIG_INTERVAL="$min_val"
			WATCHTOWER_SCHEDULE_CRON=""
			log_info "已设置: 每 $(_format_seconds_to_human "$min_val") 运行一次"
		fi
	elif [ "$mode_choice" = "2" ]; then
		WATCHTOWER_RUN_MODE="cron"
		echo -e "${CYAN}请输入 6段 Cron 表达式 (秒 分 时 日 月 周)${NC}"
		echo -e "示例: ${GREEN}0 0 4 * * *${NC}   (每天凌晨 4 点)"
		local cron_input
		read -r -p "Cron表达式 (留空保留原值): " cron_input
		if [ -n "$cron_input" ]; then
			if ! _validate_watchtower_cron_expression "$cron_input"; then
				log_warn "Cron 表达式无效，请输入 6 段合法字段。"
				return "${ERR_CONFIG}"
			fi
			WATCHTOWER_SCHEDULE_CRON="$cron_input"
			WATCHTOWER_CONFIG_INTERVAL="0"
			log_info "Cron 已设置为: $WATCHTOWER_SCHEDULE_CRON"
		else log_warn "未输入，保留原设置。"; fi
	fi
}

configure_exclusion_list() {
	local -A excluded_map=()
	local initial_exclude_list="${WATCHTOWER_EXCLUDE_LIST:-}"

	if [ -n "$initial_exclude_list" ]; then
		local old_ifs="${IFS:-}"
		IFS=','
		for container_name in $initial_exclude_list; do
			container_name=$(echo "$container_name" | xargs)
			if [ -n "$container_name" ]; then
				excluded_map["$container_name"]=1
			fi
		done
		IFS="${old_ifs}"
	fi

	while true; do
		if should_clear_screen "watchtower:configure_exclusion_list"; then clear; fi

		local -a all_containers_array=()
		while IFS= read -r line; do
			all_containers_array+=("$line")
		done < <(JB_SUDO_LOG_QUIET="true" run_with_sudo docker ps --format '{{.Names}}' 2>/dev/null || echo "")

		local -a items_array=()
		local i=0
		while [ $i -lt ${#all_containers_array[@]} ]; do
			local container="${all_containers_array[$i]}"
			local is_excluded=" "
			if [ -n "${excluded_map[$container]+_}" ]; then is_excluded="✔"; fi
			items_array+=("$((i + 1)). [${GREEN}${is_excluded}${NC}] $container")
			i=$((i + 1))
		done

		items_array+=("")

		local current_excluded_display="无"
		if [ ${#excluded_map[@]} -gt 0 ]; then
			local keys=()
			for key in "${!excluded_map[@]}"; do
				keys+=("$key")
			done
			if [ ${#keys[@]} -gt 0 ]; then
				local old_ifs="${IFS:-}"
				IFS=','
				current_excluded_display="${keys[*]}"
				IFS="${old_ifs}"
			fi
		fi

		items_array+=("${CYAN}当前忽略: ${current_excluded_display}${NC}")
		_render_menu "配置忽略更新的容器" "${items_array[@]}"

		local choice
		read -r -p "请选择 (数字切换, c 结束, 回车清空): " choice

		case "$choice" in
		c | C) break ;;
		"")
			if [ ${#excluded_map[@]} -eq 0 ]; then
				log_info "当前列表已为空。"
				sleep 1
				continue
			fi
			if confirm_action "确定要清空忽略名单吗？"; then
				excluded_map=()
				log_info "已清空。"
			else
				log_info "取消。"
			fi
			sleep 1
			continue
			;;
		*)
			local clean_choice
			clean_choice=$(echo "$choice" | tr -d ' ')
			if [ -z "$clean_choice" ]; then
				log_warn "输入无效。"
				sleep 1
				continue
			fi

			local -a selected_indices=()
			IFS=',' read -r -a selected_indices <<<"$clean_choice"
			local has_invalid_input=false

			for index in "${selected_indices[@]}"; do
				if [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 1 ] && [ "$index" -le ${#all_containers_array[@]} ]; then
					local target_container="${all_containers_array[$((index - 1))]}"
					if [ -n "${excluded_map[$target_container]+_}" ]; then
						unset "excluded_map[$target_container]"
					else
						excluded_map["$target_container"]=1
					fi
				elif [ -n "$index" ]; then
					has_invalid_input=true
				fi
			done

			if [ "$has_invalid_input" = "true" ]; then
				log_warn "输入无效。"
				sleep 1.5
			fi
			;;
		esac
	done

	local final_excluded_list=""
	if [ ${#excluded_map[@]} -gt 0 ]; then
		local keys=()
		for key in "${!excluded_map[@]}"; do
			keys+=("$key")
		done
		if [ ${#keys[@]} -gt 0 ]; then
			local old_ifs="${IFS:-}"
			IFS=','
			final_excluded_list="${keys[*]}"
			IFS="${old_ifs}"
		fi
	fi
	WATCHTOWER_EXCLUDE_LIST="$final_excluded_list"
}

configure_watchtower() {
	if _watchtower_is_running; then
		if ! confirm_action "Watchtower 正在运行。进入配置可能会覆盖当前设置，是否继续?"; then return "${ERR_OK}"; fi
	fi
	_configure_schedule
	sleep 1
	configure_exclusion_list
	local extra_args_choice
	extra_args_choice=$(_prompt_user_input "是否配置额外参数？(y/N, 当前: ${WATCHTOWER_EXTRA_ARGS:-无}): " "")
	local temp_extra_args="${WATCHTOWER_EXTRA_ARGS:-}"
	if echo "$extra_args_choice" | grep -qE '^[Yy]$'; then
		echo -e "当前额外参数: ${GREEN}${temp_extra_args:-[无]}${NC}"
		local val
		read -r -p "请输入额外参数 (回车保持, 空格清空): " val
		if [[ "$val" =~ ^\ +$ ]]; then
			temp_extra_args=""
			log_info "已清空。"
		elif [ -n "$val" ]; then temp_extra_args="$val"; fi
	fi
	local debug_choice
	debug_choice=$(_prompt_user_input "是否启用调试日志? (y/N, 当前: ${WATCHTOWER_DEBUG_ENABLED}): " "")
	local temp_debug_enabled="false"
	if echo "$debug_choice" | grep -qE '^[Yy]$'; then temp_debug_enabled="true"; fi

	local final_exclude_list_display="${WATCHTOWER_EXCLUDE_LIST:-无}"
	local mode_display
	mode_display="间隔循环 ($(_format_seconds_to_human "${WATCHTOWER_CONFIG_INTERVAL:-0}"))"
	if [[ "$WATCHTOWER_RUN_MODE" == "cron" || "$WATCHTOWER_RUN_MODE" == "aligned" ]]; then
		mode_display="Cron调度 ($WATCHTOWER_SCHEDULE_CRON)"
	fi
	local -a confirm_array=(
		"运行模式: $mode_display"
		"忽略名单: ${final_exclude_list_display//,/, }"
		"额外参数: ${temp_extra_args:-无}"
		"调试模式: $temp_debug_enabled"
	)
	_render_menu "配置确认" "${confirm_array[@]}"
	local confirm_choice
	confirm_choice=$(_prompt_for_menu_choice "")
	if echo "$confirm_choice" | grep -qE '^[Nn]$'; then
		log_info "操作已取消。"
		return "${ERR_OK}"
	fi

	WATCHTOWER_EXTRA_ARGS="$temp_extra_args"
	WATCHTOWER_DEBUG_ENABLED="$temp_debug_enabled"
	WATCHTOWER_ENABLED="true"
	save_config
	_rebuild_watchtower || return $?
	return "${ERR_OK}"
}

manage_tasks() {
	while true; do
		if should_clear_screen "watchtower:manage_tasks"; then clear; fi
		local -a items_array=(
			"1. 停止并移除服务 (uninstall) - 删除容器并清除配置"
			"2. 重建服务 (redeploy) - 应用新配置，重启 Watchtower"
		)
		_render_menu "⚙️ 服务运维 ⚙️" "${items_array[@]}"

		local choice
		choice=$(_prompt_for_menu_choice "1-2")
		case "$choice" in
		1)
			if _watchtower_exists; then
				echo -e "${RED}警告: 即将停止并移除 Watchtower 容器。${NC}"
				if confirm_action "确定要继续吗？"; then
					_remove_watchtower_container
					WATCHTOWER_ENABLED="false"
					save_config
					echo -e "${GREEN}✅ 已移除。${NC}"
				fi
			else echo -e "${YELLOW}ℹ️ Watchtower 未运行。${NC}"; fi
			press_enter_to_continue
			;;
		2)
			if _watchtower_exists; then
				if confirm_action "确定要重建 Watchtower 吗？"; then _rebuild_watchtower; else log_info "已取消。"; fi
			else
				echo -e "${YELLOW}ℹ️ Watchtower 未运行，将执行首次部署。${NC}"
				_rebuild_watchtower
			fi
			press_enter_to_continue
			;;
		"") return ;;
		*)
			log_warn "无效选项。"
			sleep 1
			;;
		esac
	done
}

# --- 辅助函数：解析日志时间戳 ---
_parse_watchtower_timestamp_from_log_line() {
	local line="$1"
	local ts
	ts=$(echo "$line" | sed -n 's/.*time="\([^"]*\)".*/\1/p' | cut -d'.' -f1 | sed 's/T/ /')
	echo "$ts"
}

_extract_interval_from_cmd() {
	local cmd_json="$1"
	local interval=""
	if command -v jq &>/dev/null; then
		interval=$(echo "$cmd_json" | jq -r 'first(range(length) as $i | select(.[$i] == "--interval") | .[$i+1] // empty)' 2>/dev/null || true)
	else
		local tokens
		read -r -a tokens <<<"$(echo "$cmd_json" | tr -d '[],"')"
		local prev=""
		for t in "${tokens[@]}"; do
			if [ "$prev" = "--interval" ]; then
				interval="$t"
				break
			fi
			prev="$t"
		done
	fi
	interval=$(echo "$interval" | sed -n 's/[^0-9]//g;p')
	echo "$interval"
}

_extract_schedule_from_env() {
	if ! command -v jq &>/dev/null; then
		echo ""
		return
	fi
	local env_json
	env_json=$(_watchtower_inspect_env 2>/dev/null || echo "[]")
	echo "$env_json" | jq -r '.[] | select(startswith("WATCHTOWER_SCHEDULE=")) | split("=")[1]' | head -n1 || true
}

get_watchtower_inspect_summary() {
	if ! _watchtower_exists; then
		echo ""
		return 2
	fi
	local cmd
	cmd=$(_watchtower_inspect_cmd 2>/dev/null || echo "[]")
	_extract_interval_from_cmd "$cmd" 2>/dev/null || true
}

get_watchtower_all_raw_logs() {
	if ! _watchtower_exists; then
		echo ""
		return 1
	fi
	_watchtower_logs_tail 2>&1 || true
}

_calculate_next_cron() {
	local cron_expr="$1"
	local sec min hour day month dow
	read -r sec min hour day month dow <<<"$cron_expr"
	if [[ "$sec" == "0" && "$min" == "0" ]]; then
		if [[ "$day" == "*" && "$month" == "*" && "$dow" == "*" ]]; then
			if [[ "$hour" == "*" ]]; then
				echo "每小时整点"
			elif [[ "$hour" =~ ^\*/([0-9]+)$ ]]; then
				echo "每 ${BASH_REMATCH[1]} 小时 (整点)"
			elif [[ "$hour" =~ ^[0-9]+$ ]]; then
				echo "每天 ${hour}:00:00"
			else echo "$cron_expr"; fi
		else echo "$cron_expr"; fi
	elif [[ "$sec" == "0" ]]; then
		if [[ "$hour" == "*" && "$day" == "*" ]]; then
			if [[ "$min" =~ ^\*/([0-9]+)$ ]]; then
				echo "每 ${BASH_REMATCH[1]} 分钟"
			else echo "$cron_expr"; fi
		else echo "$cron_expr"; fi
	else echo "$cron_expr"; fi
}

_get_watchtower_next_run_time() {
	local interval_seconds="$1"
	local raw_logs="$2"
	local schedule_env="$3"
	if [ -n "$schedule_env" ]; then
		local readable_schedule
		readable_schedule=$(_calculate_next_cron "$schedule_env")
		echo -e "${CYAN}定时任务: ${readable_schedule}${NC}"
		return
	fi
	if [ -z "$raw_logs" ] || [ -z "$interval_seconds" ]; then
		echo -e "${YELLOW}N/A${NC}"
		return
	fi
	local last_event_line
	last_event_line=$(echo "$raw_logs" | grep -E "Session done|Scheduling first run" | tail -n 1 || true)
	if [ -z "$last_event_line" ]; then
		echo -e "${YELLOW}等待首次扫描...${NC}"
		return
	fi
	local next_epoch=0
	local current_epoch
	current_epoch=$(date +%s)
	local ts_str
	ts_str=$(_parse_watchtower_timestamp_from_log_line "$last_event_line")
	if [ -n "$ts_str" ]; then
		local last_epoch=""
		if date -d "$ts_str" "+%s" >/dev/null 2>&1; then
			last_epoch=$(date -d "$ts_str" "+%s")
		elif command -v gdate >/dev/null; then last_epoch=$(gdate -d "$ts_str" "+%s"); fi
		if [ -n "$last_epoch" ]; then
			next_epoch=$((last_epoch + interval_seconds))
			local max_iterations=1000
			local iterations=0
			while [ "$next_epoch" -le "$current_epoch" ] && [ "$iterations" -lt "$max_iterations" ]; do
				next_epoch=$((next_epoch + interval_seconds))
				iterations=$((iterations + 1))
			done
			if [ "$iterations" -ge "$max_iterations" ]; then
				echo -e "${RED}计算错误${NC}"
				return
			fi
			local remaining=$((next_epoch - current_epoch))
			local h=$((remaining / 3600))
			local m=$(((remaining % 3600) / 60))
			local s=$((remaining % 60))
			printf "%b%02d时%02d分%02d秒%b" "$GREEN" "$h" "$m" "$s" "$NC"
			return
		fi
	fi
	echo -e "${YELLOW}计算中...${NC}"
}

show_container_info() {
	_print_header "容器状态看板"
	echo -e "${CYAN}说明: 下表列出了当前 Docker 主机上的容器。${NC}"
	if ! command -v docker &>/dev/null; then
		log_error "Docker 未找到。"
		return
	fi
	JB_SUDO_LOG_QUIET="true" run_with_sudo docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.RunningFor}}"
	echo ""
	press_enter_to_continue
}

show_watchtower_details() {
	while true; do
		if should_clear_screen "watchtower:show_watchtower_details"; then clear; fi
		local title="📊 详情与管理 📊"
		local interval raw_logs COUNTDOWN schedule_env
		interval=$(get_watchtower_inspect_summary 2>/dev/null || true)
		raw_logs=$(get_watchtower_all_raw_logs 2>/dev/null || true)
		schedule_env=$(_extract_schedule_from_env 2>/dev/null || true)
		COUNTDOWN=$(_get_watchtower_next_run_time "${interval}" "${raw_logs}" "${schedule_env}")

		local -a content_lines_array=(
			"⏱️  ${CYAN}当前状态${NC}"
			"    ${YELLOW}下一次扫描:${NC} ${COUNTDOWN}"
			""
			"📜  ${CYAN}最近日志摘要 (最后 5 行)${NC}"
		)

		local logs_tail
		logs_tail=$(echo "$raw_logs" | tail -n 5)
		while IFS= read -r line; do
			content_lines_array+=("    ${line:0:80}...")
		done <<<"$logs_tail"

		_render_menu "$title" "${content_lines_array[@]}"

		local pick
		read -r -p "$(echo -e "> ${ORANGE}[1]${NC}实时日志 ${ORANGE}[2]${NC}容器看板 ${ORANGE}[3]${NC}触发扫描 (↩ 返回): ")" pick </dev/tty

		case "$pick" in
		1)
			if _watchtower_exists; then
				echo -e "\n按 Ctrl+C 停止..."
				trap '' INT
				_watchtower_logs_follow || true
				trap 'echo -e "\n操作被中断。"; exit '"${ERR_RUNTIME}"'' INT
			else echo -e "\n${RED}Watchtower 未运行。${NC}"; fi
			press_enter_to_continue
			;;
		2) show_container_info ;;
		3)
			run_watchtower_once
			press_enter_to_continue
			;;
		*) break ;;
		esac
	done
	trap 'printf "\n操作被中断。\n" >&2; exit '"${ERR_RUNTIME}"'' INT
}

# --- 修复: 高级参数编辑器 (移除冗余选项) ---
view_and_edit_config() {
	local -a config_items=(
		"忽略名单|WATCHTOWER_EXCLUDE_LIST|string_list"
		"额外参数|WATCHTOWER_EXTRA_ARGS|string"
		"调试模式|WATCHTOWER_DEBUG_ENABLED|bool"
		"主镜像仓库|WATCHTOWER_IMAGE_PRIMARY_REPO|string"
		"回退镜像仓库|WATCHTOWER_IMAGE_FALLBACK_REPO|string"
		"镜像标签|WATCHTOWER_IMAGE_TAG|string"
		"允许本地旧镜像回退|WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK|bool"
		"Docker API 版本|WATCHTOWER_DOCKER_API_VERSION|string"
		"运行模式|WATCHTOWER_RUN_MODE|schedule"
		"检测频率|WATCHTOWER_CONFIG_INTERVAL|interval"
		"IPv4 接口|WATCHTOWER_IPV4_INTERFACE|string"
		"IPv6 接口|WATCHTOWER_IPV6_INTERFACE|string"
	)

	while true; do
		if should_clear_screen "watchtower:view_and_edit_config"; then clear; fi
		load_config
		local -a content_lines_array=()
		local i
		for i in "${!config_items[@]}"; do
			local item="${config_items[$i]}"
			local label
			label=$(echo "$item" | cut -d'|' -f1)
			local var_name
			var_name=$(echo "$item" | cut -d'|' -f2)
			local type
			type=$(echo "$item" | cut -d'|' -f3)
			local current_value="${!var_name}"
			local display_text=""
			local color="${CYAN}"

			case "$type" in
			string)
				if [ -n "$current_value" ]; then
					if [[ "$var_name" == "TG_BOT_TOKEN" || "$var_name" == "TG_CHAT_ID" ]]; then
						display_text=$(_mask_string "$current_value" 6)
						color="${GREEN}"
					else
						color="${GREEN}"
						display_text="$current_value"
					fi
				else
					color="${RED}"
					display_text="未设置"
				fi
				;;
			string_list)
				if [ -n "$current_value" ]; then
					color="${YELLOW}"
					display_text="${current_value//,/, }"
				else
					color="${CYAN}"
					display_text="无"
				fi
				;;
			bool)
				if [ "$current_value" = "true" ]; then
					color="${GREEN}"
					display_text="是"
				else
					color="${CYAN}"
					display_text="否"
				fi
				;;
			interval)
				if [[ "$WATCHTOWER_RUN_MODE" == "cron" || "$WATCHTOWER_RUN_MODE" == "aligned" ]]; then
					display_text="禁用 (已启用Cron)"
					color="${YELLOW}"
				else
					display_text=$(_format_seconds_to_human "$current_value")
					if [ "$display_text" != "N/A" ] && [ -n "$current_value" ]; then
						color="${GREEN}"
					else
						color="${RED}"
						display_text="未设置"
					fi
				fi
				;;
			schedule)
				if [[ "$current_value" == "cron" || "$current_value" == "aligned" ]]; then
					display_text="Cron调度 (${WATCHTOWER_SCHEDULE_CRON})"
					color="${GREEN}"
				else
					display_text="间隔循环 ($(_format_seconds_to_human "${WATCHTOWER_CONFIG_INTERVAL:-0}"))"
					color="${CYAN}"
				fi
				;;
			esac
			content_lines_array+=("$(printf "%2d. %s: %s%s%s" "$((i + 1))" "$label" "$color" "$display_text" "$NC")")
		done

		_render_menu "⚙️ 高级参数编辑器 ⚙️" "${content_lines_array[@]}"

		local choice
		choice=$(_prompt_for_menu_choice "1-${#config_items[@]}")
		if [ -z "$choice" ]; then return; fi
		if ! echo "$choice" | grep -qE '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#config_items[@]}" ]; then
			log_warn "无效选项。"
			sleep 1
			continue
		fi

		local selected_index=$((choice - 1))
		local selected_item="${config_items[$selected_index]}"
		local label
		label=$(echo "$selected_item" | cut -d'|' -f1)
		local var_name
		var_name=$(echo "$selected_item" | cut -d'|' -f2)
		local type
		type=$(echo "$selected_item" | cut -d'|' -f3)
		local current_value="${!var_name}"

		case "$type" in
		string | string_list)
			if [ "$var_name" = "WATCHTOWER_EXCLUDE_LIST" ]; then
				configure_exclusion_list
			else
				local masked_value="[未设置]"
				if [ -n "$current_value" ]; then
					if [[ "$var_name" == "TG_BOT_TOKEN" || "$var_name" == "TG_CHAT_ID" ]]; then
						masked_value=$(_mask_string "$current_value" 6)
					else
						masked_value="$current_value"
					fi
				fi
				echo -e "当前 ${label}: ${GREEN}${masked_value}${NC}"
				echo -e "${YELLOW}提示: 直接回车保持不变，输入空格并回车清空${NC}"
				local val
				read -r -p "请输入新值: " val

				if [[ "$val" =~ ^[[:space:]]+$ ]]; then
					declare "$var_name"=""
					log_info "'$label' 已清空。"
				elif [ -n "$val" ]; then
					declare "$var_name"="$val"
					log_info "'$label' 已更新。"
				else
					log_info "'$label' 保持不变。"
				fi
			fi
			;;
		bool)
			local new_value_input
			new_value_input=$(_prompt_user_input "是否启用 '$label'? (y/N, 当前: $current_value): " "")
			if echo "$new_value_input" | grep -qE '^[Yy]$'; then declare "$var_name"="true"; else declare "$var_name"="false"; fi
			;;
		interval)
			if [[ "$WATCHTOWER_RUN_MODE" == "cron" || "$WATCHTOWER_RUN_MODE" == "aligned" ]]; then
				log_warn "当前处于定时任务模式，设置间隔不会生效。请修改 '运行模式'。"
				sleep 2
			else
				local new_value
				new_value=$(_prompt_for_interval "${current_value:-300}" "为 '$label' 设置新间隔")
				if [ -n "$new_value" ]; then declare "$var_name"="$new_value"; fi
			fi
			;;
		schedule) _configure_schedule ;;
		esac
		save_config
		_prompt_rebuild_if_needed
		sleep 1
	done
}

config_center_menu() {
	while true; do
		if should_clear_screen "watchtower:config_center_menu"; then clear; fi
		local -a items=(
			"1. 通知与安全设置 (Telegram/别名/加密)"
			"2. 高级参数编辑器"
		)
		_render_menu "⚙️ 配置中心 ⚙️" "统一管理通知、安全与高级参数" "" "${items[@]}"
		local c
		c=$(_prompt_for_menu_choice "1-2")
		case "$c" in
		1) notification_menu ;;
		2) view_and_edit_config ;;
		"") return 0 ;;
		*)
			log_warn "无效选项。"
			sleep 1
			;;
		esac
	done
}

main_menu() {
	while true; do
		if should_clear_screen "watchtower:main_menu"; then clear; fi
		load_config
		local docker_ready=0
		if command -v docker >/dev/null 2>&1; then
			docker_ready=1
		fi

		local STATUS_RAW="未运行"
		if [ "${docker_ready}" -eq 1 ]; then
			if _watchtower_is_running; then STATUS_RAW="已启动"; fi
		else
			STATUS_RAW="未安装"
		fi

		local STATUS_COLOR
		if [ "$STATUS_RAW" = "已启动" ]; then
			STATUS_COLOR="${GREEN}已启动${NC}"
		elif [ "$STATUS_RAW" = "未安装" ]; then
			STATUS_COLOR="${YELLOW}Docker未安装${NC}"
		else STATUS_COLOR="${RED}未运行${NC}"; fi

		local interval="" raw_logs="" schedule_env=""
		if [ "$STATUS_RAW" = "已启动" ]; then
			interval=$(get_watchtower_inspect_summary 2>/dev/null || true)
			raw_logs=$(get_watchtower_all_raw_logs 2>/dev/null || true)
			schedule_env=$(_extract_schedule_from_env 2>/dev/null || true)
		fi

		local COUNTDOWN
		COUNTDOWN=$(_get_watchtower_next_run_time "${interval}" "${raw_logs}" "${schedule_env}")

		local notify_mode="${CYAN}关闭${NC}"
		if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then notify_mode="${GREEN}Telegram${NC}"; fi

		local config_mtime container_created warning_msg=""
		config_mtime=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo 0)
		if [ "${docker_ready}" -eq 1 ]; then
			container_created=$(_watchtower_inspect_created 2>/dev/null || echo "")
		else
			container_created=""
		fi

		if [ "$STATUS_RAW" = "已启动" ] && [ -n "$container_created" ]; then
			local container_ts
			container_ts=$(date -d "$container_created" +%s 2>/dev/null || echo 0)
			if [ "$config_mtime" -gt "$((container_ts + 5))" ]; then
				warning_msg=" ${YELLOW}⚠️ 配置未生效 (需重建)${NC}"
				STATUS_COLOR="${YELLOW}待重启${NC}"
			fi
		fi

		local header_text="Watchtower 自动更新管理器"

		local -a content_array=(
			"🕝 服务运行状态: ${STATUS_COLOR}${warning_msg}"
			"🔔 消息通知渠道: ${notify_mode}"
			"⏳ 下一次扫描: ${COUNTDOWN}"
			""
			"主菜单："
			"1. 部署/重新配置服务 (核心设置)"
			"2. 配置中心 (通知+高级参数)"
			"3. 服务运维 (停止/重建)"
			"4. 实时日志与容器看板"
		)

		_render_menu "$header_text" "${content_array[@]}"

		local choice
		choice=$(_prompt_for_menu_choice "1-4")
		case "$choice" in
		1)
			configure_watchtower
			local rc=$?
			if [ "$rc" -ne "${ERR_OK}" ]; then log_warn "配置流程未正常完成 (code: $rc)"; fi
			press_enter_to_continue
			;;
		2) config_center_menu ;;
		3) manage_tasks ;;
		4) show_watchtower_details ;;
		"") return "${ERR_RUNTIME}" ;;
		*)
			log_warn "无效选项。"
			sleep 1
			;;
		esac
	done
}

main() {
	init_runtime
	watchtower_validate_args "$@"
	self_elevate_or_die "$@"
	log_info "配置文件路径: ${CONFIG_FILE}"
	[ -f "$CONFIG_FILE" ] && load_config

	case "${1:-}" in
	--diagnose)
		watchtower_diagnose
		exit $?
		;;
	--export-config)
		watchtower_export_config
		exit $?
		;;
	--import-config)
		watchtower_import_config "${2:-}"
		exit $?
		;;
	--run-once)
		run_watchtower_once true
		exit $?
		;;
	--systemd-start)
		log_info "Starting Watchtower via systemd..."
		_rebuild_watchtower
		exit $?
		;;
	--systemd-stop)
		log_info "Stopping Watchtower via systemd..."
		_remove_watchtower_container
		exit "${ERR_OK}"
		;;
	--generate-systemd-service)
		log_warn "此功能已移除，请使用 Docker 的 --restart unless-stopped 参数实现开机自启"
		exit "${ERR_OK}"
		;;
	esac

	trap 'printf "\n操作被中断。\n" >&2; exit '"${ERR_RUNTIME}"'' INT TERM
	local menu_rc
	if main_menu; then
		menu_rc="${ERR_OK}"
	else
		menu_rc="$?"
	fi

	if [ "$menu_rc" -eq "${ERR_RUNTIME}" ]; then
		exit "${ERR_RUNTIME}"
	fi
	exit "${ERR_OK}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
