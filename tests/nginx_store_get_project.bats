#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.store.project.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "_get_project_json returns first match" {
  run bash -c '
    set -euo pipefail
    source "$1"
    td="$(mktemp -d /tmp/nginx.store.project.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT

    export PROJECTS_METADATA_FILE="$td/projects.json"
    printf "%s\n" "[" >"$PROJECTS_METADATA_FILE"
    printf "%s\n" "{\"domain\":\"demo.example.com\",\"resolved_port\":\"8080\"}," >>"$PROJECTS_METADATA_FILE"
    printf "%s\n" "{\"domain\":\"demo.example.com\",\"resolved_port\":\"9090\"}" >>"$PROJECTS_METADATA_FILE"
    printf "%s\n" "]" >>"$PROJECTS_METADATA_FILE"

    result=$(_get_project_json "demo.example.com")
    [ "$(jq -r .resolved_port <<<"$result")" = "8080" ]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "_get_project_json returns empty when missing" {
  run bash -c '
    set -euo pipefail
    source "$1"
    td="$(mktemp -d /tmp/nginx.store.project.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT

    export PROJECTS_METADATA_FILE="$td/projects.json"
    printf "%s\n" "[]" >"$PROJECTS_METADATA_FILE"

    result=$(_get_project_json "missing.example.com")
    [ -z "$result" ]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}
