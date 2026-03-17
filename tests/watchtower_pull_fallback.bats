#!/usr/bin/env bats

@test "watchtower pull fallback logs local image info" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    log_warn() { printf "%s\n" "$*"; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "image" ] && [ "$3" = "inspect" ]; then
        printf "%s\n" "sha256:abcdef1234567890|2026-03-16T00:00:00Z"
        return 0
      fi
      return 1
    }

    _log_watchtower_pull_failure "containrrr/watchtower"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"本地镜像: containrrr/watchtower"* ]]
}
