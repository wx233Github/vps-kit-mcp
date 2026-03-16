#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.tx.output.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "tx marker default hidden in output" {
  run bash -c '
    set -euo pipefail
    source "$1"
    IS_INTERACTIVE_MODE=true
    LOG_HIDE_CTX_PREFIX=true
    LOG_HIDE_TX_PREFIX=true
    _tx_emit_marker "STATE_CREATED" "transaction created"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"transaction created"* ]]
  [[ "$output" != *"[TX:"* ]]
}

@test "tx marker visible when disabled" {
  run bash -c '
    set -euo pipefail
    source "$1"
    IS_INTERACTIVE_MODE=true
    LOG_HIDE_CTX_PREFIX=true
    LOG_HIDE_TX_PREFIX=false
    _tx_emit_marker "STATE_CREATED" "transaction created"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[TX:STATE_CREATED] transaction created"* ]]
}

@test "log_message supports output override" {
  run bash -c '
    set -euo pipefail
    source "$1"
    IS_INTERACTIVE_MODE=true
    LOG_HIDE_CTX_PREFIX=true
    log_message INFO "plain" "HIGHLIGHT"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HIGHLIGHT"* ]]
  [[ "$output" != *"plain"* ]]
}

@test "rebuild output omits ansi in non-tty" {
  run bash -c '
    set -euo pipefail
    source "$1"
    IS_INTERACTIVE_MODE=true
    LOG_HIDE_CTX_PREFIX=true
    d="example.com"
    rebuild_msg="重建配置文件: ${d} ..."
    rebuild_output="$rebuild_msg"
    if [ -t 1 ]; then
      rebuild_output="${CYAN}重建配置文件:${NC} ${GREEN}${d}${NC} ..."
    fi
    log_message INFO "$rebuild_msg" "$rebuild_output"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"重建配置文件: example.com ..."* ]]
  [[ "$output" != *"\\033"* ]]
}
