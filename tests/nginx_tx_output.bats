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
