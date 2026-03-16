#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.backend.fallback.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "backend target uses fallback port" {
  run bash -c '
    set -euo pipefail
    source "$1"
    IS_INTERACTIVE_MODE=true

    prompt_input() {
      printf "%s\n" "${2:-}"
      return 0
    }

    result=$(_prompt_backend_target_for_project "{}" "" "4000")
    [ "$result" = "local_port	4000" ]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}
