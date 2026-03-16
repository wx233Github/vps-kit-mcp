#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.rebuild.summary.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "rebuild prints compact summaries with strategy" {
  run bash -c '
    set -euo pipefail
    source "$1"
    IS_INTERACTIVE_MODE=true
    LOG_HIDE_CTX_PREFIX=true

    td="$(mktemp -d /tmp/nginx.rebuild.summary.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT
    export PROJECTS_METADATA_FILE="$td/projects.json"
    cat >"$PROJECTS_METADATA_FILE" <<EOF
[
  {"domain":"one.example.com","resolved_port":"8080"},
  {"domain":"two.example.com","resolved_port":"9090"}
]
EOF

    confirm_or_cancel() { return 0; }
    safe_rm() { return 0; }
    _get_project_json() { jq -c --arg d "$1" ".[] | select(.domain == \$d)" "$PROJECTS_METADATA_FILE"; }
    _apply_project_transaction() {
      if [ "$1" = "one.example.com" ]; then
        NGINX_CONF_GEN=$((NGINX_CONF_GEN + 1))
        NGINX_RELOAD_STRATEGY_CACHE="systemctl"
        NGINX_RELOAD_STRATEGY_CACHE_TS=$(date +%s)
        return 0
      fi
      NGINX_RELOAD_STRATEGY_CACHE="hup_master_pid:123"
      NGINX_RELOAD_STRATEGY_CACHE_TS=$(date +%s)
      return 0
    }

    _rebuild_all_nginx_configs
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ 重建完成: one.example.com"* ]]
  [[ "$output" == *"strategy=systemctl"* ]]
  [[ "$output" == *"✅ 无变化: two.example.com"* ]]
  [[ "$output" == *"strategy=hup_master_pid:123"* ]]
}
