#!/usr/bin/env bats
# Coverage Matrix
# - prompt_menu_choice 空回车（返回上一层）后，press_enter_to_continue 不再要求确认
# - 选了具体项时仍保留停屏
#
# Fixture Conventions
# - 直接 source lib/nginx_core.sh；交互输入由 _read_input_prompt 桩提供。

setup() {
  CORE_PATH="${BATS_TEST_DIRNAME%/tests}/lib/nginx_core.sh"
}

@test "回车返回上一层后，不再要求再按一次 Enter" {
  run bash -c '
    source "$1" 2>/dev/null
    JB_NONINTERACTIVE="false"; IS_INTERACTIVE_MODE="true"
    _read_input_prompt() { REPLY=""; printf "%s" "$1"; return 0; }
    c=$(prompt_menu_choice "1-2" "true")
    press_enter_to_continue
  ' _ "$CORE_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" != *"按 Enter 键继续"* ]]
}

@test "选了具体项后，仍然停屏一次" {
  run bash -c '
    source "$1" 2>/dev/null
    JB_NONINTERACTIVE="false"; IS_INTERACTIVE_MODE="true"
    _read_input_prompt() { REPLY="1"; printf "%s" "$1"; return 0; }
    c=$(prompt_menu_choice "1-2" "true")
    press_enter_to_continue
  ' _ "$CORE_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"按 Enter 键继续"* ]]
}
