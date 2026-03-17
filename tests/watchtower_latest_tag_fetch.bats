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
