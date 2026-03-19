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
    WATCHTOWER_NOTIFY_ON_NO_UPDATES="false"
    save_config

    WATCHTOWER_IMAGE_PRIMARY_REPO=""
    WATCHTOWER_IMAGE_FALLBACK_REPO=""
    WATCHTOWER_IMAGE_TAG=""
    WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK=""
    WATCHTOWER_DOCKER_API_VERSION=""
    WATCHTOWER_NOTIFY_ON_NO_UPDATES=""

    load_config
    printf "%s|%s|%s|%s|%s|%s\n" \
      "$WATCHTOWER_IMAGE_PRIMARY_REPO" \
      "$WATCHTOWER_IMAGE_FALLBACK_REPO" \
      "$WATCHTOWER_IMAGE_TAG" \
      "$WATCHTOWER_ALLOW_LOCAL_IMAGE_FALLBACK" \
      "$WATCHTOWER_DOCKER_API_VERSION" \
      "$WATCHTOWER_NOTIFY_ON_NO_UPDATES"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.com/custom/watchtower|docker.io/custom/watchtower|stable|false|1.40|false"* ]]
}

@test "watchtower load_config falls back to module notify default from launcher env" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    WATCHTOWER_CONF_NOTIFY_ON_NO_UPDATES="false"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    load_config
    printf "%s\n" "$WATCHTOWER_NOTIFY_ON_NO_UPDATES"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"false"* ]]
}

@test "watchtower load_config repairs invalid persisted field values" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_CONFIG_INTERVAL="abc"
WATCHTOWER_RUN_MODE="weird"
WATCHTOWER_SCHEDULE_CRON="0 99 * * * *"
WATCHTOWER_IMAGE_PRIMARY_REPO="bad repo"
WATCHTOWER_IMAGE_TAG="bad tag!"
WATCHTOWER_DOCKER_API_VERSION="v1"
WATCHTOWER_HOST_ALIAS="bad alias"
WATCHTOWER_IPV4_INTERFACE="eth0;bad"
WATCHTOWER_NOTIFY_ON_NO_UPDATES="maybe"
EOF

    load_config
    printf "%s|%s|%s|%s|%s|%s|%s\n" \
      "$WATCHTOWER_CONFIG_INTERVAL" \
      "$WATCHTOWER_RUN_MODE" \
      "$WATCHTOWER_IMAGE_PRIMARY_REPO" \
      "$WATCHTOWER_IMAGE_TAG" \
      "$WATCHTOWER_DOCKER_API_VERSION" \
      "$WATCHTOWER_HOST_ALIAS" \
      "${WATCHTOWER_IPV4_INTERFACE:-empty}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"21600|interval|ghcr.io/containrrr/watchtower|latest||DockerNode|empty"* ]]
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

@test "watchtower stable env hash ignores notification template drift" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    env_a=$(mktemp)
    env_b=$(mktemp)
    cat >"$env_a" <<"EOF"
TZ=Asia/Shanghai
JB_WATCHTOWER_HOST_ALIAS=node-a
JB_WATCHTOWER_IPV4_INTERFACE=eth0
WATCHTOWER_NOTIFICATION_REPORT=true
WATCHTOWER_NOTIFICATION_TEMPLATE=first-template
EOF
    cat >"$env_b" <<"EOF"
TZ=Asia/Shanghai
JB_WATCHTOWER_HOST_ALIAS=node-a
JB_WATCHTOWER_IPV4_INTERFACE=eth0
WATCHTOWER_NOTIFICATION_REPORT=true
WATCHTOWER_NOTIFICATION_TEMPLATE=second-template
EOF

    printf "%s|%s\n" "$(_stable_watchtower_env_hash "$env_a")" "$(_stable_watchtower_env_hash "$env_b")"
  '
  [ "$status" -eq 0 ]
  hash_pair="$(printf "%s" "$output" | tail -n1)"
  left_hash="${hash_pair%%|*}"
  right_hash="${hash_pair##*|}"
  [ -n "$left_hash" ]
  [ "$left_hash" = "$right_hash" ]
}

@test "watchtower stable env hash still detects meaningful drift" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    env_a=$(mktemp)
    env_b=$(mktemp)
    cat >"$env_a" <<"EOF"
TZ=Asia/Shanghai
JB_WATCHTOWER_HOST_ALIAS=node-a
DOCKER_API_VERSION=1.40
WATCHTOWER_NOTIFICATION_TEMPLATE=first-template
EOF
    cat >"$env_b" <<"EOF"
TZ=Asia/Shanghai
JB_WATCHTOWER_HOST_ALIAS=node-a
DOCKER_API_VERSION=1.54
WATCHTOWER_NOTIFICATION_TEMPLATE=second-template
EOF

    printf "%s|%s\n" "$(_stable_watchtower_env_hash "$env_a")" "$(_stable_watchtower_env_hash "$env_b")"
  '
  [ "$status" -eq 0 ]
  hash_pair="$(printf "%s" "$output" | tail -n1)"
  left_hash="${hash_pair%%|*}"
  right_hash="${hash_pair##*|}"
  [ -n "$left_hash" ]
  [ "$left_hash" != "$right_hash" ]
}

@test "watchtower cron validator accepts valid six-field expression" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _validate_watchtower_cron_expression "0 0 4 * * *"
  '
  [ "$status" -eq 0 ]
}

@test "watchtower cron validator rejects invalid field count" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _validate_watchtower_cron_expression "0 4 * * *"
  '
  [ "$status" -eq 1 ]
}

@test "watchtower env file rejects invalid cron schedule" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    WATCHTOWER_RUN_MODE="cron"
    WATCHTOWER_SCHEDULE_CRON="0 99 * * * *"
    target_file=$(mktemp)
    _generate_env_file "$target_file"
  '
  [ "$status" -eq 5 ]
  [[ "$output" == *"Watchtower Cron 配置无效"* ]]
}

@test "watchtower import_config rejects invalid extra args and keeps live config" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _get_ip_address() { printf "%s\n" ""; }
    _resolve_watchtower_docker_api_version() { return 0; }

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_IMAGE_TAG="stable"
EOF

    candidate=$(mktemp)
    cat >"$candidate" <<"EOF"
WATCHTOWER_IMAGE_TAG="broken"
WATCHTOWER_EXTRA_ARGS="--cleanup"
EOF

    if watchtower_import_config "$candidate"; then
      printf "%s\n" "unexpected-success"
      exit 1
    fi

    load_config
    printf "%s\n" "$WATCHTOWER_IMAGE_TAG"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"stable"* ]]
  [[ "$output" != *"unexpected-success"* ]]
}

@test "watchtower import_config rejects invalid cron and keeps live config" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _get_ip_address() { printf "%s\n" ""; }
    _resolve_watchtower_docker_api_version() { return 0; }

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_IMAGE_TAG="stable"
EOF

    candidate=$(mktemp)
    cat >"$candidate" <<"EOF"
WATCHTOWER_IMAGE_TAG="broken"
WATCHTOWER_RUN_MODE="cron"
WATCHTOWER_SCHEDULE_CRON="0 99 * * * *"
EOF

    if watchtower_import_config "$candidate"; then
      printf "%s\n" "unexpected-success"
      exit 1
    fi

    load_config
    printf "%s\n" "$WATCHTOWER_IMAGE_TAG"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"stable"* ]]
  [[ "$output" != *"unexpected-success"* ]]
}

@test "watchtower import_config accepts valid candidate and replaces live config" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _get_ip_address() { printf "%s\n" ""; }
    _resolve_watchtower_docker_api_version() { return 0; }

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_IMAGE_TAG="stable"
EOF

    candidate=$(mktemp)
    cat >"$candidate" <<"EOF"
WATCHTOWER_IMAGE_TAG="nightly"
WATCHTOWER_EXTRA_ARGS="--label-enable"
WATCHTOWER_NOTIFY_ON_NO_UPDATES="false"
EOF

    watchtower_import_config "$candidate"
    load_config
    printf "%s|%s\n" "$WATCHTOWER_IMAGE_TAG" "$WATCHTOWER_NOTIFY_ON_NO_UPDATES"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"nightly|false"* ]]
}

@test "watchtower import_config rejects invalid host alias and keeps live config" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    _get_ip_address() { printf "%s\n" ""; }
    _resolve_watchtower_docker_api_version() { return 0; }

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_IMAGE_TAG="stable"
EOF

    candidate=$(mktemp)
    cat >"$candidate" <<"EOF"
WATCHTOWER_IMAGE_TAG="broken"
WATCHTOWER_HOST_ALIAS="bad alias"
EOF

    if watchtower_import_config "$candidate"; then
      printf "%s\n" "unexpected-success"
      exit 1
    fi

    load_config
    printf "%s\n" "$WATCHTOWER_IMAGE_TAG"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"stable"* ]]
  [[ "$output" != *"unexpected-success"* ]]
}
