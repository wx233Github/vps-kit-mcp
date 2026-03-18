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

@test "watchtower pull falls back to docker hub" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    log_warn() { printf "%s\n" "$*"; }
    log_info() { printf "%s\n" "$*"; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "pull" ] && [ "$3" = "ghcr.io/containrrr/watchtower:latest" ]; then
        return 1
      fi
      if [ "$1" = "docker" ] && [ "$2" = "pull" ] && [ "$3" = "containrrr/watchtower:latest" ]; then
        return 0
      fi
      return 1
    }

    selected=$(_select_watchtower_image "ghcr.io/containrrr/watchtower:latest" "containrrr/watchtower:latest")
    printf "%s\n" "$selected"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"已回退使用 Docker Hub 镜像"* ]]
  [[ "$output" == *"containrrr/watchtower:latest"* ]]
}

@test "watchtower resolves image from configured repo and tag" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    WATCHTOWER_IMAGE_PRIMARY_REPO="example.com/custom/watchtower"
    WATCHTOWER_IMAGE_FALLBACK_REPO=""
    WATCHTOWER_IMAGE_TAG="stable"
    log_warn() { printf "%s\n" "$*"; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "pull" ] && [ "$3" = "example.com/custom/watchtower:stable" ]; then
        return 0
      fi
      return 1
    }

    selected=$(_resolve_watchtower_image)
    printf "%s\n" "$selected"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.com/custom/watchtower:stable"* ]]
}

@test "watchtower local image fallback can be disabled" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    log_warn() { printf "%s\n" "$*"; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "pull" ]; then
        return 1
      fi
      if [ "$1" = "docker" ] && [ "$2" = "image" ] && [ "$3" = "inspect" ]; then
        printf "%s\n" "sha256:abcdef1234567890|2026-03-16T00:00:00Z"
        return 0
      fi
      return 1
    }

    if _select_watchtower_image "ghcr.io/containrrr/watchtower:latest" "containrrr/watchtower:latest" false; then
      printf "%s\n" "unexpected-success"
    else
      printf "%s\n" "fallback-disabled"
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"已禁用本地旧镜像回退"* ]]
  [[ "$output" == *"fallback-disabled"* ]]
}
