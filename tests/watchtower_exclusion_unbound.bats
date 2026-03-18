#!/usr/bin/env bats

@test "watchtower exclusion list handles empty map" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    should_clear_screen() { return 1; }
    _render_menu() { :; }
    run_with_sudo() { :; }
    confirm_action() { return 1; }

    printf "%s\n" "c" | configure_exclusion_list
  '
  [ "$status" -eq 0 ]
}

@test "watchtower exclusion list matches container names literally" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    trace_file=$(mktemp)
    load_config() { :; }
    _generate_env_file() { :; }
    _resolve_watchtower_image() { printf "%s\n" "containrrr/watchtower:latest"; }
    _wait_for_container_healthy() { return 0; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "ps" ] && [ "$3" = "--format" ]; then
        printf "%s\n" "app-v2.1"
        printf "%s\n" "db[1]"
        printf "%s\n" "plain"
        printf "%s\n" "watchtower"
        return 0
      fi
      if [ "$1" = "docker" ] && [ "$2" = "run" ]; then
        printf "%s\n" "$*" >"$trace_file"
        return 0
      fi
      return 1
    }

    WATCHTOWER_EXCLUDE_LIST="app-v2.1,db[1]"
    WATCHTOWER_RUN_MODE="interval"
    WATCHTOWER_CONFIG_INTERVAL="300"
    _start_watchtower_container_logic "300" "test" true
    cat "$trace_file"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"plain"* ]]
  [[ "$output" != *"app-v2.1"* ]]
  [[ "$output" != *"db[1]"* ]]
  [[ "$output" != *" watchtower"* ]]
}
