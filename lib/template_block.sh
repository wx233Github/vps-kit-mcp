#!/usr/bin/env bash
# 模板块代数：在站点配置中标记、提取、计数、校验、对比与快照定位。
# 由 nginx.sh 在启动时 source；纯函数，无顶层副作用。

_template_block_wrap() {
	local template_id="${1:-}"
	local payload="${2:-}"
	local payload_hash=""
	payload_hash=$(_template_payload_hash "$payload")
	cat <<EOF
# NGINX_TEMPLATE_START:${template_id}
# Template: $(_template_id_to_name "$template_id")
# Hash: ${payload_hash}
${payload}
# NGINX_TEMPLATE_END:${template_id}
EOF
}

_extract_template_blocks_by_ids() {
	local content="${1:-}"
	shift || true
	local ids=("$@")
	if [ "${#ids[@]}" -eq 0 ]; then
		printf '%s\n' "$content"
		return 0
	fi

	local patterns_json
	patterns_json=$(printf '%s\n' "${ids[@]}" | jq -R . | jq -s .)

	jq -r --arg text "$content" --argjson ids "$patterns_json" '
    def remove_block($id):
      ($id | gsub("[][(){}.*+?|^$\\\\-]"; "\\\\\\\\&")) as $esc
      | $text
      | gsub("(?ms)^# NGINX_TEMPLATE_START:" + $esc + "\\n.*?^# NGINX_TEMPLATE_END:" + $esc + "\\n?"; "");
    reduce $ids[] as $id ($text; ($id | gsub("[][(){}.*+?|^$\\\\-]"; "\\\\\\\\&")) as $esc | gsub("(?ms)^# NGINX_TEMPLATE_START:" + $esc + "\\n.*?^# NGINX_TEMPLATE_END:" + $esc + "\\n?"; ""))
  '
}

_extract_all_template_blocks() {
	local content="${1:-}"
	jq -r --arg text "$content" '
    $text
    | gsub("(?ms)^# NGINX_TEMPLATE_START:[^\\n]+\\n.*?^# NGINX_TEMPLATE_END:[^\\n]+\\n?"; "")
  '
}

_template_block_marker_balance_ok() {
	local content="${1:-}"
	local starts=0
	local ends=0
	local line=""
	while IFS= read -r line; do
		case "$line" in
		'# NGINX_TEMPLATE_START:'*) starts=$((starts + 1)) ;;
		'# NGINX_TEMPLATE_END:'*) ends=$((ends + 1)) ;;
		esac
	done <<<"$content"
	[ "$starts" -eq "$ends" ]
}

_count_template_blocks() {
	local content="${1:-}"
	local count=0
	local line=""
	while IFS= read -r line; do
		case "$line" in
		'# NGINX_TEMPLATE_START:'*) count=$((count + 1)) ;;
		esac
	done <<<"$content"
	printf '%s\n' "$count"
}

_count_lines() {
	local content="${1:-}"
	if [ -z "$content" ]; then
		printf '%s\n' "0"
		return 0
	fi
	awk 'END{print NR}' <<<"$content"
}

_print_template_diff_summary() {
	local before="${1:-}"
	local after="${2:-}"
	local before_blocks after_blocks before_lines after_lines
	before_blocks=$(_count_template_blocks "$before")
	after_blocks=$(_count_template_blocks "$after")
	before_lines=$(_count_lines "$before")
	after_lines=$(_count_lines "$after")
	printf '%b' "${CYAN}变更摘要:${NC} 模板块 ${before_blocks} -> ${after_blocks}，行数 ${before_lines} -> ${after_lines}\n"
}

_template_operation_confirm_or_auto() {
	local prompt_text="${1:-确认继续?}"
	local default_yesno="${2:-y}"
	if [ "$TEMPLATE_BATCH_AUTO_CONFIRM" = "true" ]; then
		return 0
	fi
	if [ "$IS_INTERACTIVE_MODE" != "true" ] && [ -n "$TEMPLATE_MODE" ]; then
		log_message INFO "非交互模板模式：自动确认执行。"
		return 0
	fi
	confirm_or_cancel "$prompt_text" "$default_yesno"
}

_template_contains_id() {
	local target="${1:-}"
	shift || true
	local id=""
	for id in "$@"; do
		if [ "$id" = "$target" ]; then
			return 0
		fi
	done
	return 1
}

_dedupe_template_ids() {
	local id=""
	local -a uniq=()
	for id in "$@"; do
		[ -z "$id" ] && continue
		if ! _template_contains_id "$id" "${uniq[@]}"; then
			uniq+=("$id")
		fi
	done
	printf '%s\n' "${uniq[*]}"
}

_parse_template_vars_raw() {
	local raw="${1:-}"
	local token=""
	local key=""
	local val=""
	TEMPLATE_VARS=()
	raw="${raw// /}"
	[ -z "$raw" ] && return 0
	IFS=',' read -r -a parts <<<"$raw"
	for token in "${parts[@]}"; do
		[ -z "$token" ] && continue
		if [[ "$token" != *=* ]]; then
			return 1
		fi
		key="${token%%=*}"
		val="${token#*=}"
		if ! [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
			return 1
		fi
		if ! [[ "$val" =~ ^[A-Za-z0-9._:-]+$ ]]; then
			return 1
		fi
		TEMPLATE_VARS["$key"]="$val"
	done
	return 0
}

_validate_template_vars_for_selection() {
	local -a selected=("$@")
	local id=""
	local key=""
	local allowed=""
	local vkey=""
	if [ "${#TEMPLATE_VARS[@]}" -eq 0 ]; then
		return 0
	fi
	for id in "${selected[@]}"; do
		[ -z "$id" ] && continue
		# shellcheck disable=SC2016
		allowed+=" $(_manifest_query --arg id "$id" '.templates[] | select(.id == $id) | (.vars // {} | keys | join(" "))' 2>/dev/null || true)"
	done
	for vkey in "${!TEMPLATE_VARS[@]}"; do
		if [[ " $allowed " != *" $vkey "* ]]; then
			log_message ERROR "模板变量未被当前模板集合声明: ${vkey}"
			return 1
		fi
	done
	for id in "${selected[@]}"; do
		[ -z "$id" ] && continue
		# shellcheck disable=SC2016
		while IFS=$'\t' read -r key pattern; do
			[ -z "$key" ] && continue
			if [ -n "${TEMPLATE_VARS[$key]+x}" ] && [ -n "$pattern" ] && ! [[ "${TEMPLATE_VARS[$key]}" =~ $pattern ]]; then
				log_message ERROR "模板变量校验失败: ${key}=${TEMPLATE_VARS[$key]} 不匹配 ${pattern}"
				return 1
			fi
		done < <(_manifest_query --arg id "$id" '.templates[] | select(.id == $id) | (.vars // {}) | to_entries[]? | [.key, (.value.pattern // "")] | @tsv' 2>/dev/null)
	done
	return 0
}

_json_escape() {
	tm_json_escape "$@"
}

_emit_template_cli_summary() {
	local mode="${1:-}"
	local domain_expr="${2:-}"
	local matched="${3:-0}"
	local ok="${4:-0}"
	local fail="${5:-0}"
	local code="${6:-0}"
	local precheck="${7:-false}"
	if [ "${TEMPLATE_OUTPUT_JSON:-false}" != "true" ]; then
		return 0
	fi
	printf '{"mode":%s,"domain_expr":%s,"matched":%s,"ok":%s,"fail":%s,"precheck":%s,"exit_code":%s}\n' \
		"$(_json_escape "$mode")" \
		"$(_json_escape "$domain_expr")" \
		"$matched" \
		"$ok" \
		"$fail" \
		"$precheck" \
		"$code"
}

_rotate_template_audit_log_if_needed() {
	tm_rotate_template_audit_log_if_needed "$@"
}

_append_template_audit_log() {
	tm_append_template_audit_log "$@"
}

_snapshot_epoch_from_file() {
	local file_name="${1:-}"
	local base=""
	local stamp=""
	base=$(basename "$file_name" .json.bak)
	stamp="${base##*_}"
	if [[ ! "$stamp" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
		return 1
	fi
	date -d "${stamp:0:8} ${stamp:9:2}:${stamp:11:2}:${stamp:13:2}" +%s 2>/dev/null
}

_find_best_snapshot_for_domain() {
	local domain="${1:-}"
	local target_epoch="${2:-0}"
	local file=""
	local best_file=""
	local best_epoch=0
	local ts=0
	local newest_file=""
	local newest_epoch=0
	shopt -s nullglob
	for file in "$JSON_BACKUP_DIR"/project_"$domain"_*.json.bak; do
		ts=$(_snapshot_epoch_from_file "$file" 2>/dev/null || printf '%s' "0")
		if [ "$ts" -gt "$newest_epoch" ]; then
			newest_epoch="$ts"
			newest_file="$file"
		fi
		if [ "$target_epoch" -gt 0 ] && [ "$ts" -le "$target_epoch" ] && [ "$ts" -ge "$best_epoch" ]; then
			best_epoch="$ts"
			best_file="$file"
		fi
	done
	shopt -u nullglob
	if [ -n "$best_file" ]; then
		printf '%s\n' "$best_file"
		return 0
	fi
	if [ -n "$newest_file" ]; then
		printf '%s\n' "$newest_file"
		return 0
	fi
	return 1
}

_template_impact_report() {
	tm_template_impact_report "$@"
}

_rollback_templates_by_op() {
	tm_rollback_templates_by_op "$@"
}

_template_audit_report() {
	tm_template_audit_report
}
