#!/usr/bin/env bats

@test "watchtower defaults disable no-update notifications" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    load_config
    [ "$WATCHTOWER_NOTIFY_ON_NO_UPDATES" = "false" ]
  '
  [ "$status" -eq 0 ]
}

@test "watchtower notification toggle saves explicit true value" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _prompt_rebuild_if_needed() { :; }
    _prompt_user_input() { printf "%s\n" "y"; }

    load_config
    _configure_notify_on_no_updates
    load_config

    [ "$WATCHTOWER_NOTIFY_ON_NO_UPDATES" = "true" ]
    grep "^WATCHTOWER_NOTIFY_ON_NO_UPDATES=\"true\"$" "$CONFIG_FILE"
  '
  [ "$status" -eq 0 ]
}

@test "watchtower notification toggle falls back to false on empty answer" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _prompt_rebuild_if_needed() { :; }
    _prompt_user_input() { printf "%s\n" ""; }

    WATCHTOWER_NOTIFY_ON_NO_UPDATES="true"
    _configure_notify_on_no_updates
    load_config

    [ "$WATCHTOWER_NOTIFY_ON_NO_UPDATES" = "false" ]
    grep "^WATCHTOWER_NOTIFY_ON_NO_UPDATES=\"false\"$" "$CONFIG_FILE"
  '
  [ "$status" -eq 0 ]
}
