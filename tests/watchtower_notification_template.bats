#!/usr/bin/env bats

@test "watchtower notification report follows enabled no-update setting" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _get_ip_address() { printf "%s\n" ""; }
    _resolve_watchtower_docker_api_version() { return 0; }
    TG_BOT_TOKEN="token"
    TG_CHAT_ID="chat"
    WATCHTOWER_NOTIFY_ON_NO_UPDATES="true"
    target_file=$(mktemp)
    _generate_env_file "$target_file"
    grep "^WATCHTOWER_NOTIFICATION_REPORT=true" "$target_file"
    grep "^WATCHTOWER_NOTIFICATION_TEMPLATE=" "$target_file"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"WATCHTOWER_NOTIFICATION_REPORT=true"* ]]
}

@test "watchtower notification template gates empty updates when disabled" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _get_ip_address() { printf "%s\n" ""; }
    _resolve_watchtower_docker_api_version() { return 0; }
    TG_BOT_TOKEN="token"
    TG_CHAT_ID="chat"
    WATCHTOWER_NOTIFY_ON_NO_UPDATES="false"
    target_file=$(mktemp)
    _generate_env_file "$target_file"
    grep "^WATCHTOWER_NOTIFICATION_REPORT=true" "$target_file"
    grep "if or (gt (len .Updated) 0) (gt (len .Failed) 0)" "$target_file"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"WATCHTOWER_NOTIFICATION_REPORT=true"* ]]
}
