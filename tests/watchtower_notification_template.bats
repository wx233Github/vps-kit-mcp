#!/usr/bin/env bats

@test "watchtower notification report disabled" {
  run bash -c 'grep -q "WATCHTOWER_NOTIFICATION_REPORT=false" /root/aa/vps-kit-mcp/tools/Watchtower.sh'
  [ "$status" -eq 0 ]
}

@test "watchtower notification template gates empty updates" {
  run bash -c 'grep -q "if or (gt (len .Updated) 0) (gt (len .Failed) 0)" /root/aa/vps-kit-mcp/tools/Watchtower.sh'
  [ "$status" -eq 0 ]
}
