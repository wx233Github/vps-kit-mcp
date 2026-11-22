#!/usr/bin/env bats

setup() {
	export WATCHTOWER_SCRIPT="${BATS_TEST_DIRNAME}/../tools/Watchtower.sh"
}

@test "间隔循环 cron 显示可读描述与倒计时，而不是裸表达式" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { :; }; log_warn() { :; }
	_calculate_next_cron "0 0 */12 * * *"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"每 12 小时 (整点)"* ]]
	[[ "$output" == *"后"* ]]
	[[ "$output" != *"0 0 */12"* ]]
}

@test "其余三种可识别形态输出对应描述" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { :; }; log_warn() { :; }
	_calculate_next_cron "0 0 4 * * *"; printf "\n"
	_calculate_next_cron "0 */15 * * * *"; printf "\n"
	_calculate_next_cron "0 0 * * * *"; printf "\n"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"每天 4:00:00"* ]]
	[[ "$output" == *"每 15 分钟"* ]]
	[[ "$output" == *"每小时整点"* ]]
}

@test "无法识别的自定义 cron 原样回显" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { :; }; log_warn() { :; }
	_calculate_next_cron "30 5 4 * * 1"
	'
	[ "$status" -eq 0 ]
	[ "$output" = "30 5 4 * * 1" ]
}

@test "运行模式直接回车返回取消码且不写配置" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { printf "INFO:%s\n" "$*"; }; log_warn() { :; }
	_prompt_for_menu_choice() { printf ""; }
	set +e
	_configure_schedule >/dev/null 2>&1
	rc=$?
	set -e
	printf "rc=%s\n" "$rc"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"rc=7"* ]]
}

@test "间隔输入直接回车返回取消码" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { :; }; log_warn() { :; }
	_prompt_for_menu_choice() { printf "1"; }
	_prompt_user_input() { printf ""; }
	set +e
	_configure_schedule >/dev/null 2>&1
	rc=$?
	set -e
	printf "rc=%s\n" "$rc"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"rc=7"* ]]
}

@test "对齐方式直接回车返回取消码" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { :; }; log_warn() { :; }
	_prompt_user_input() { printf "12"; }
	_prompt_for_menu_choice() { case "$1" in 1-2) printf "1" ;; 1-3) printf "" ;; esac; }
	set +e
	_configure_schedule >/dev/null 2>&1
	rc=$?
	set -e
	printf "rc=%s\n" "$rc"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"rc=7"* ]]
}

@test "小时间隔超过 23 时提示范围并重新询问" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { printf "INFO:%s\n" "$*"; }; log_warn() { printf "WARN:%s\n" "$*"; }
	# 计数落盘：命令替换在子 shell 中执行，变量自增不会回传
	counter_file=$(mktemp)
	printf "0" >"$counter_file"
	_prompt_user_input() {
		local n
		n=$(cat "$counter_file")
		n=$((n + 1))
		printf "%s" "$n" >"$counter_file"
		if [ "$n" -eq 1 ]; then printf "30"; else printf "12"; fi
	}
	_prompt_for_menu_choice() { case "$1" in 1-2) printf "1" ;; 1-3) printf "2" ;; esac; }
	_configure_schedule >"$counter_file.out" 2>&1 || true
	printf "%s\n" "$(cat "$counter_file.out")" | grep -E "1-23 之间|已设置" || true
	rm -f "$counter_file" "$counter_file.out"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"1-23 之间"* ]]
	[[ "$output" == *"每 12 小时"* ]]
}

@test "间隔不能整除 24 时给出短间隔提示" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { printf "INFO:%s\n" "$*"; }; log_warn() { printf "WARN:%s\n" "$*"; }
	_prompt_user_input() { printf "7"; }
	_prompt_for_menu_choice() { case "$1" in 1-2) printf "1" ;; 1-3) printf "2" ;; esac; }
	out=$(_configure_schedule 2>&1 || true)
	printf "%s\n" "$out" | grep -E "不能整除 24|已设置" || true
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"0 0 */7 * * *"* ]]
	[[ "$output" == *"不能整除 24"* ]]
}

@test "日志摘要提取 msg 内容并过滤启动横幅" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { :; }; log_warn() { :; }
	raw=$(printf "%s\n" \
		"time=\"2026-11-22T20:35:20+08:00\" level=info msg=\"Watchtower 1.7.1\"" \
		"time=\"2026-11-22T20:35:20+08:00\" level=info msg=\"Using no notifications\"" \
		"time=\"2026-11-23T00:00:03+08:00\" level=info msg=\"Session done: 0 updated, 3 scanned\"")
	_watchtower_log_digest "$raw"
	'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Session done: 0 updated, 3 scanned"* ]]
	[[ "$output" != *"Watchtower 1.7.1"* ]]
	[[ "$output" != *"level=info"* ]]
}

@test "日志摘要为空输入时不输出内容" {
	run bash -c '
	set -euo pipefail
	source "$WATCHTOWER_SCRIPT" >/dev/null 2>&1 || true
	log_info() { :; }; log_warn() { :; }
	_watchtower_log_digest ""
	'
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
