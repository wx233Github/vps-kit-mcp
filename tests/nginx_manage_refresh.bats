#!/usr/bin/env bats

setup() {
	REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
	SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
	LIB_PATH="$(mktemp /tmp/nginx.manage.refresh.XXXXXX.sh)"
	sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
	rm -f "$LIB_PATH"
}

@test "select_item_and_act 在动作后会从 projects 文件刷新列表" {
	run bash -c '
		set -euo pipefail
		source "$1"
		td="$(mktemp -d /tmp/nginx.manage.refresh.XXXXXX)"
		trap "rm -rf \"$td\"" EXIT

		export PROJECTS_METADATA_FILE="$td/projects.json"
		printf "%s\n" "[{\"domain\":\"demo.example.com\",\"resolved_port\":\"https://old:443\"}]" >"$PROJECTS_METADATA_FILE"

		printf "%s" "0" >"$td/prompt_count"
		_display_projects_list() {
			printf "%s\n" "$1" >>"$td/render.log"
		}
		prompt_input() {
			local calls
			calls=$(cat "$td/prompt_count")
			calls=$((calls + 1))
			printf "%s" "$calls" >"$td/prompt_count"
			case "$calls" in
			1) printf "%s\n" "1" ;;
			2) printf "%s\n" "" ;;
			esac
		}
		_manage_http_actions() {
			printf "%s\n" "[{\"domain\":\"demo.example.com\",\"resolved_port\":\"107.161.92.157:18789\"}]" >"$PROJECTS_METADATA_FILE"
			return 0
		}

		list_json=$(jq . "$PROJECTS_METADATA_FILE")
		count=$(jq "length" <<<"$list_json")
		select_item_and_act "$list_json" "$count" "请输入序号选择项目 (回车返回)" "domain" _manage_http_actions _display_projects_list "$PROJECTS_METADATA_FILE" || true

		test "$(wc -l <"$td/render.log")" -ge 2
		grep -q "https://old:443" "$td/render.log"
		grep -q "107.161.92.157:18789" "$td/render.log"
	' _ "$LIB_PATH"
	[ "$status" -eq 0 ]
}
