#!/usr/bin/env bats

setup() {
	export REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
	DOCKER_PATH="$(mktemp /tmp/docker.ui.theme.XXXXXX.sh)"
	CERT_PATH="$(mktemp /tmp/cert.ui.theme.XXXXXX.sh)"
	awk '/^UTILS_PATH=/ {print "UTILS_PATH=\"/tmp/__missing_utils__\""; next} {print}' "${REPO_ROOT}/docker.sh" | sed '$d' >"$DOCKER_PATH"
	awk '/^UTILS_PATH=/ {print "UTILS_PATH=\"/tmp/__missing_utils__\""; next} {print}' "${REPO_ROOT}/cert.sh" | sed '$d' >"$CERT_PATH"
}

teardown() {
	rm -f "$DOCKER_PATH" "$CERT_PATH"
}

@test "docker main_menu 在 retro-launcher 下通过 utils prompt 生成中文 footer" {
	run bash -c '
    set -euo pipefail
    source $REPO_ROOT/utils.sh
    source "$1"
    JB_UI_THEME="retro-launcher"
    JB_MENU_CONTEXT="submenu"
    prompt=$(ui_build_prompt_text "1-3" "" "submenu")
    [[ "$prompt" == *"请输入编号，直接回车返回。"* ]]
  ' _ "$DOCKER_PATH"
	[ "$status" -eq 0 ]
}

@test "cert main_menu 在 retro-launcher 下通过 utils prompt 生成中文 footer" {
	run bash -c '
    set -euo pipefail
    source $REPO_ROOT/utils.sh
    source "$1"
    JB_UI_THEME="retro-launcher"
    JB_MENU_CONTEXT="submenu"
    prompt=$(ui_build_prompt_text "1-3" "" "submenu")
    [[ "$prompt" == *"请输入编号，直接回车返回。"* ]]
  ' _ "$CERT_PATH"
	[ "$status" -eq 0 ]
}
