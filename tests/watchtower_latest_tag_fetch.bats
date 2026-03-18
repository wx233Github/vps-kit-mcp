#!/usr/bin/env bats

# 校验 Watchtower 配置驱动的镜像/API 行为

@test "watchtower load_config applies image/api defaults when config missing" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    load_config
    printf "%s|%s|%s|%s|%s\n" \
      "$WATCHTOWER_IMAGE_PRIMARY_REPO" \
      "$WATCHTOWER_IMAGE_FALLBACK_REPO" \
      "$WATCHTOWER_IMAGE_TAG" \
      "$WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK" \
      "${WATCHTOWER_DOCKER_API_VERSION:-auto}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/containrrr/watchtower|containrrr/watchtower|latest|true|auto"* ]]
}

@test "watchtower save_config round-trips image/api settings" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    WATCHTOWER_IMAGE_PRIMARY_REPO="example.com/custom/watchtower"
    WATCHTOWER_IMAGE_FALLBACK_REPO="docker.io/custom/watchtower"
    WATCHTOWER_IMAGE_TAG="stable"
    WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK="false"
    WATCHTOWER_DOCKER_API_VERSION="1.40"
    save_config

    WATCHTOWER_IMAGE_PRIMARY_REPO=""
    WATCHTOWER_IMAGE_FALLBACK_REPO=""
    WATCHTOWER_IMAGE_TAG=""
    WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK=""
    WATCHTOWER_DOCKER_API_VERSION=""

    load_config
    printf "%s|%s|%s|%s|%s\n" \
      "$WATCHTOWER_IMAGE_PRIMARY_REPO" \
      "$WATCHTOWER_IMAGE_FALLBACK_REPO" \
      "$WATCHTOWER_IMAGE_TAG" \
      "$WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK" \
      "$WATCHTOWER_DOCKER_API_VERSION"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.com/custom/watchtower|docker.io/custom/watchtower|stable|false|1.40"* ]]
}

@test "watchtower env file writes configured docker api version" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _get_ip_address() { printf "%s\n" ""; }
    WATCHTOWER_DOCKER_API_VERSION="1.40"
    target_file=$(mktemp)
    _generate_env_file "$target_file"
    grep "^DOCKER_API_VERSION=" "$target_file"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_API_VERSION=1.40"* ]]
}

@test "watchtower env file auto-detects docker min api version when config empty" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    stub_dir=$(mktemp -d)
    HOME="$tmp_home"
    cat >"$stub_dir/docker" <<"EOF"
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$stub_dir/docker"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh
    PATH="$stub_dir:$PATH"

    _get_ip_address() { printf "%s\n" ""; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "version" ] && [ "$3" = "--format" ]; then
        case "$4" in
        "{{.Server.MinAPIVersion}}") printf "%s" "1.40"; return 0 ;;
        "{{.Server.APIVersion}}") printf "%s" "1.54"; return 0 ;;
        esac
      fi
      return 1
    }

    target_file=$(mktemp)
    _generate_env_file "$target_file"
    grep "^DOCKER_API_VERSION=" "$target_file"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_API_VERSION=1.40"* ]]
}

@test "watchtower env file falls back to server api version when min api unavailable" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    stub_dir=$(mktemp -d)
    HOME="$tmp_home"
    cat >"$stub_dir/docker" <<"EOF"
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$stub_dir/docker"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh
    PATH="$stub_dir:$PATH"

    _get_ip_address() { printf "%s\n" ""; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "version" ] && [ "$3" = "--format" ]; then
        case "$4" in
        "{{.Server.MinAPIVersion}}") printf "%s" "<no value>"; return 0 ;;
        "{{.Server.APIVersion}}") printf "%s" "1.54"; return 0 ;;
        esac
      fi
      return 1
    }

    target_file=$(mktemp)
    _generate_env_file "$target_file"
    grep "^DOCKER_API_VERSION=" "$target_file"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_API_VERSION=1.54"* ]]
}
