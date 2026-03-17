#!/usr/bin/env bats

# 校验最新 release tag 的获取与回退逻辑

@test "watchtower latest tag parses redirect url" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    # 记录日志到输出，便于断言
    log_warn() { printf "%s\n" "$*"; }

    stub_dir=$(mktemp -d /tmp/watchtower.tag.stub.XXXXXX)
    cat >"$stub_dir/curl" <<"EOF"
#!/usr/bin/env bash
printf "%s" "https://github.com/containrrr/watchtower/releases/tag/v1.7.1"
EOF
    chmod +x "$stub_dir/curl"
    PATH="$stub_dir:$PATH"

    tag=$(_get_watchtower_latest_release_tag)
    printf "%s\n" "$tag"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1.7.1"* ]]
}

@test "watchtower latest tag falls back when curl missing" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    # 记录日志到输出，便于断言
    log_warn() { printf "%s\n" "$*"; }

    PATH="/tmp/watchtower.no.curl"
    if _get_watchtower_latest_release_tag; then
      printf "%s\n" "ok"
    else
      printf "%s\n" "fallback"
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"回退 latest"* ]]
  [[ "$output" == *"fallback"* ]]
}

@test "watchtower tag fallback strips leading v" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    log_warn() { printf "%s\n" "$*" >&2; }
    log_info() { printf "%s\n" "$*" >&2; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "pull" ]; then
        case "$3" in
        ghcr.io/containrrr/watchtower:v1.7.1) return 1 ;;
        containrrr/watchtower:v1.7.1) return 1 ;;
        ghcr.io/containrrr/watchtower:1.7.1) return 0 ;;
        *) return 1 ;;
        esac
      fi
      return 1
    }

    image=$(_select_watchtower_image_with_tag_fallback "v1.7.1" "1.7.1" "ghcr.io/containrrr/watchtower" "containrrr/watchtower")
    printf "%s\n" "$image"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"尝试 1.7.1"* ]]
  [[ "$output" == *"ghcr.io/containrrr/watchtower:1.7.1"* ]]
}
