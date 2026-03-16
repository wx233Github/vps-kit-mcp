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
