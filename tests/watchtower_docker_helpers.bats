#!/usr/bin/env bats

@test "watchtower docker helpers preserve command contract" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    trace_file=$(mktemp)
    run_with_sudo() {
      printf "%s|" "$@" >>"$trace_file"
      printf "\n" >>"$trace_file"
      case "$1|$2|${3:-}|${4:-}|${5:-}|${6:-}" in
      docker\|ps\|--format\|{{.Names}}\|\|)
        printf "%s\n" "watchtower"
        return 0
        ;;
      docker\|ps\|-a\|--format\|{{.Names}}\|)
        printf "%s\n" "watchtower"
        return 0
        ;;
      docker\|inspect\|watchtower\|--format\|{{json\ .Config.Env}}\|)
        printf "%s\n" "[\"WATCHTOWER_SCHEDULE=0 0 * * * *\"]"
        return 0
        ;;
      docker\|inspect\|watchtower\|--format\|{{json\ .Config.Cmd}}\|)
        printf "%s\n" "[\"--interval\",\"300\"]"
        return 0
        ;;
      docker\|inspect\|--format\|{{.Created}}\|watchtower\|)
        printf "%s\n" "2026-03-19T00:00:00Z"
        return 0
        ;;
      docker\|logs\|--tail\|500\|watchtower\|)
        printf "%s\n" "tail-log"
        return 0
        ;;
      docker\|logs\|-f\|--tail\|100\|watchtower)
        printf "%s\n" "follow-log"
        return 0
        ;;
      docker\|rm\|-f\|watchtower\|\|)
        printf "%s\n" "remove-noise"
        printf "%s\n" "remove-error" >&2
        return 1
        ;;
      esac
      return 1
    }

    if _watchtower_is_running; then running=yes; else running=no; fi
    if _watchtower_exists; then exists=yes; else exists=no; fi
    env_json=$(_watchtower_inspect_env)
    cmd_json=$(_watchtower_inspect_cmd)
    created=$(_watchtower_inspect_created)
    tail_logs=$(_watchtower_logs_tail)
    follow_logs=$(_watchtower_logs_follow)
    remove_output="$(_remove_watchtower_container 2>&1)"

    printf "state=%s|%s\n" "$running" "$exists"
    printf "env=%s\n" "$env_json"
    printf "cmd=%s\n" "$cmd_json"
    printf "created=%s\n" "$created"
    printf "tail=%s\n" "$tail_logs"
    printf "follow=%s\n" "$follow_logs"
    printf "remove=%s\n" "${remove_output:-<empty>}"
    cat "$trace_file"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"state=yes|yes"* ]]
  [[ "$output" == *"env=[\"WATCHTOWER_SCHEDULE=0 0 * * * *\"]"* ]]
  [[ "$output" == *"cmd=[\"--interval\",\"300\"]"* ]]
  [[ "$output" == *"created=2026-03-19T00:00:00Z"* ]]
  [[ "$output" == *"tail=tail-log"* ]]
  [[ "$output" == *"follow=follow-log"* ]]
  [[ "$output" == *"remove=<empty>"* ]]
  [[ "$output" == *$'docker|ps|--format|{{.Names}}|\ndocker|ps|-a|--format|{{.Names}}|'* ]]
  [[ "$output" == *$'docker|inspect|watchtower|--format|{{json .Config.Env}}|\ndocker|inspect|watchtower|--format|{{json .Config.Cmd}}|'* ]]
  [[ "$output" == *$'docker|inspect|--format|{{.Created}}|watchtower|\ndocker|logs|--tail|500|watchtower|\ndocker|logs|-f|--tail|100|watchtower|\ndocker|rm|-f|watchtower|'* ]]
}

@test "watchtower absent-container callers keep empty fallbacks" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "ps" ] && [ "$3" = "--format" ]; then
        return 0
      fi
      if [ "$1" = "docker" ] && [ "$2" = "ps" ] && [ "$3" = "-a" ] && [ "$4" = "--format" ]; then
        return 0
      fi
      return 1
    }

    schedule_env=$(_extract_schedule_from_env 2>/dev/null || true)
    inspect_summary=$(get_watchtower_inspect_summary 2>/dev/null || true)
    raw_logs=$(get_watchtower_all_raw_logs 2>/dev/null || true)
    created=$(_watchtower_inspect_created 2>/dev/null || echo "")

    printf "schedule=<%s>\n" "$schedule_env"
    printf "summary=<%s>\n" "$inspect_summary"
    printf "logs=<%s>\n" "$raw_logs"
    printf "created=<%s>\n" "$created"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"schedule=<>"* ]]
  [[ "$output" == *"summary=<>"* ]]
  [[ "$output" == *"logs=<>"* ]]
  [[ "$output" == *"created=<>"* ]]
}

@test "watchtower extra args parser accepts simple safe flags" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    WATCHTOWER_EXTRA_ARGS="--label-enable --include-stopped"
    _parse_watchtower_extra_args
  '

  [ "$status" -eq 0 ]
  [[ "$output" == $'--label-enable\n--include-stopped' ]]
}

@test "watchtower extra args parser rejects managed flags" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    WATCHTOWER_EXTRA_ARGS="--cleanup"
    _parse_watchtower_extra_args
  '

  [ "$status" -eq 5 ]
  [[ "$output" == *"额外参数禁止覆盖封装器已管理的选项"* ]]
}

@test "watchtower extra args parser rejects unsupported tokens" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    WATCHTOWER_EXTRA_ARGS="--label-enable --name;bad"
    _parse_watchtower_extra_args
  '

  [ "$status" -eq 5 ]
  [[ "$output" == *"额外参数包含不受支持的 token"* ]]
}

@test "watchtower rebuild restores previous container when replacement start fails" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    trace_file=$(mktemp)
    WATCHTOWER_CONFIG_INTERVAL="300"
    _watchtower_exists() { return 0; }
    _start_watchtower_container_logic() { return 1; }
    prune_dangling_images() { printf "%s\n" "unexpected-prune" >>"$trace_file"; return 0; }
    run_with_sudo() {
      printf "%s|" "$@" >>"$trace_file"
      printf "\n" >>"$trace_file"
      return 0
    }

    if _rebuild_watchtower; then
      printf "%s\n" "unexpected-success"
      exit 1
    fi
    cat "$trace_file"
  '

  [ "$status" -eq 0 ]
  [[ "$output" != *"unexpected-success"* ]]
  [[ "$output" != *"unexpected-prune"* ]]
  [[ "$output" == *$'docker|rename|watchtower|watchtower-backup|'* ]]
  [[ "$output" == *$'docker|rm|-f|watchtower|'* ]]
  [[ "$output" == *$'docker|rename|watchtower-backup|watchtower|'* ]]
}

@test "watchtower rebuild removes backup after successful replacement" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    trace_file=$(mktemp)
    WATCHTOWER_CONFIG_INTERVAL="300"
    _watchtower_exists() { return 0; }
    _start_watchtower_container_logic() { return 0; }
    prune_dangling_images() { printf "%s\n" "prune-called" >>"$trace_file"; return 0; }
    run_with_sudo() {
      printf "%s|" "$@" >>"$trace_file"
      printf "\n" >>"$trace_file"
      return 0
    }

    _rebuild_watchtower
    cat "$trace_file"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *$'docker|rename|watchtower|watchtower-backup|'* ]]
  [[ "$output" == *$'docker|rm|-f|watchtower-backup|'* ]]
  [[ "$output" == *"prune-called"* ]]
}

@test "watchtower rebuild avoids clobbering an existing backup container name" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    trace_file=$(mktemp)
    WATCHTOWER_CONFIG_INTERVAL="300"
    _watchtower_exists() { return 0; }
    _start_watchtower_container_logic() { return 1; }
    run_with_sudo() {
      printf "%s|" "$@" >>"$trace_file"
      printf "\n" >>"$trace_file"
      if [ "$1" = "docker" ] && [ "$2" = "ps" ] && [ "$3" = "-a" ] && [ "$4" = "--format" ]; then
        printf "%s\n" "watchtower"
        printf "%s\n" "watchtower-backup"
        return 0
      fi
      return 0
    }

    if _rebuild_watchtower; then
      printf "%s\n" "unexpected-success"
      exit 1
    fi
    cat "$trace_file"
  '

  [ "$status" -eq 0 ]
  [[ "$output" != *"unexpected-success"* ]]
  [[ "$output" != *$'docker|rm|-f|watchtower-backup|'* ]]
  [[ "$output" == *$'docker|rename|watchtower|watchtower-backup-rebuild-1|'* ]]
  [[ "$output" == *$'docker|rename|watchtower-backup-rebuild-1|watchtower|'* ]]
}

@test "watchtower backup name resolver skips repeated rebuild suffix collisions" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "ps" ] && [ "$3" = "-a" ] && [ "$4" = "--format" ]; then
        printf "%s\n" "watchtower"
        printf "%s\n" "watchtower-backup"
        printf "%s\n" "watchtower-backup-rebuild-1"
        printf "%s\n" "watchtower-backup-rebuild-2"
        return 0
      fi
      return 1
    }

    _resolve_watchtower_backup_container_name
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"watchtower-backup-rebuild-3"* ]]
}

@test "watchtower diagnose reports snapshot visibility and effective schedule mode" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh
    docker() { return 0; }
    _get_ip_address() { printf "%s\n" ""; }

    backup_last_run=""
    if [ -f "$ENV_FILE_LAST_RUN" ]; then
      backup_last_run=$(mktemp)
      cp -f "$ENV_FILE_LAST_RUN" "$backup_last_run"
    fi
    cleanup() {
      rm -f "$ENV_FILE_LAST_RUN"
      if [ -n "$backup_last_run" ] && [ -f "$backup_last_run" ]; then
        cp -f "$backup_last_run" "$ENV_FILE_LAST_RUN"
      fi
    }
    trap cleanup EXIT

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_RUN_MODE="cron"
WATCHTOWER_DOCKER_API_VERSION="1.40"
EOF
    mkdir -p "$(dirname "$ENV_FILE_LAST_RUN")"
    load_config
    _generate_env_file "$ENV_FILE_LAST_RUN"

    run_with_sudo() {
      case "$1|$2|${3:-}|${4:-}|${5:-}" in
      docker\|version\|--format\|{{.Server.MinAPIVersion}}\|)
        printf "%s" "1.40"
        return 0
        ;;
      docker\|ps\|--format\|{{.Names}}\|)
        printf "%s\n" "watchtower"
        return 0
        ;;
      docker\|ps\|-a\|--format\|{{.Names}})
        printf "%s\n" "watchtower"
        return 0
        ;;
      docker\|inspect\|watchtower\|--format\|{{json\ .Config.Env}})
        printf "%s\n" "[\"WATCHTOWER_SCHEDULE=0 0 * * * *\"]"
        return 0
        ;;
      docker\|inspect\|watchtower\|--format\|{{json\ .Config.Cmd}})
        printf "%s\n" "[]"
        return 0
        ;;
      docker\|inspect\|--format\|{{.Created}}\|watchtower)
        printf "%s\n" "2026-03-19T00:00:00Z"
        return 0
        ;;
      esac
      return 1
    }

    watchtower_diagnose
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"config_exists=yes"* ]]
  [[ "$output" == *"config_mtime="* ]]
  [[ "$output" == *"env_file_last_run_exists=yes"* ]]
  [[ "$output" == *"env_file_last_run_mtime="* ]]
  [[ "$output" == *"env_file_last_run_consistency=match"* ]]
  [[ "$output" == *"watchtower_run_mode_configured=cron"* ]]
  [[ "$output" == *"watchtower_run_mode_effective_hint=schedule"* ]]
  [[ "$output" == *"watchtower_container_exists=yes"* ]]
  [[ "$output" == *"watchtower_container_created=2026-03-19T00:00:00Z"* ]]
}

@test "watchtower diagnose reports env snapshot drift against current config" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh
    docker() { return 0; }
    _get_ip_address() { printf "%s\n" ""; }

    backup_last_run=""
    if [ -f "$ENV_FILE_LAST_RUN" ]; then
      backup_last_run=$(mktemp)
      cp -f "$ENV_FILE_LAST_RUN" "$backup_last_run"
    fi
    cleanup() {
      rm -f "$ENV_FILE_LAST_RUN"
      if [ -n "$backup_last_run" ] && [ -f "$backup_last_run" ]; then
        cp -f "$backup_last_run" "$ENV_FILE_LAST_RUN"
      fi
    }
    trap cleanup EXIT

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_RUN_MODE="cron"
WATCHTOWER_DOCKER_API_VERSION="1.40"
WATCHTOWER_HOST_ALIAS="node-a"
EOF
    mkdir -p "$(dirname "$ENV_FILE_LAST_RUN")"
    load_config
    _generate_env_file "$ENV_FILE_LAST_RUN"

    cat >"$CONFIG_FILE" <<"EOF"
WATCHTOWER_RUN_MODE="cron"
WATCHTOWER_DOCKER_API_VERSION="1.40"
WATCHTOWER_HOST_ALIAS="node-b"
EOF

    run_with_sudo() {
      case "$1|$2|${3:-}|${4:-}|${5:-}" in
      docker\|version\|--format\|{{.Server.MinAPIVersion}}\|)
        printf "%s" "1.40"
        return 0
        ;;
      docker\|ps\|--format\|{{.Names}}\|)
        printf "%s\n" "watchtower"
        return 0
        ;;
      docker\|ps\|-a\|--format\|{{.Names}})
        printf "%s\n" "watchtower"
        return 0
        ;;
      docker\|inspect\|watchtower\|--format\|{{json\ .Config.Env}})
        printf "%s\n" "[\"WATCHTOWER_SCHEDULE=0 0 * * * *\"]"
        return 0
        ;;
      docker\|inspect\|watchtower\|--format\|{{json\ .Config.Cmd}})
        printf "%s\n" "[]"
        return 0
        ;;
      docker\|inspect\|--format\|{{.Created}}\|watchtower)
        printf "%s\n" "2026-03-19T00:00:00Z"
        return 0
        ;;
      esac
      return 1
    }

    watchtower_diagnose
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"env_file_last_run_consistency=drift"* ]]
}

@test "watchtower diagnose keeps stable n-a fallbacks when container and snapshot are absent" {
  run bash -c '
    set -euo pipefail
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh
    docker() { return 0; }

    backup_last_run=""
    if [ -f "$ENV_FILE_LAST_RUN" ]; then
      backup_last_run=$(mktemp)
      cp -f "$ENV_FILE_LAST_RUN" "$backup_last_run"
      rm -f "$ENV_FILE_LAST_RUN"
    fi
    cleanup() {
      rm -f "$ENV_FILE_LAST_RUN"
      if [ -n "$backup_last_run" ] && [ -f "$backup_last_run" ]; then
        cp -f "$backup_last_run" "$ENV_FILE_LAST_RUN"
      fi
    }
    trap cleanup EXIT

    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "version" ] && [ "$3" = "--format" ]; then
        printf "%s" "1.54"
        return 0
      fi
      if [ "$1" = "docker" ] && [ "$2" = "ps" ] && [ "$3" = "--format" ]; then
        return 0
      fi
      if [ "$1" = "docker" ] && [ "$2" = "ps" ] && [ "$3" = "-a" ] && [ "$4" = "--format" ]; then
        return 0
      fi
      return 1
    }

    watchtower_diagnose
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"config_exists=no"* ]]
  [[ "$output" == *"config_mtime=n/a"* ]]
  [[ "$output" == *"env_file_last_run_exists=no"* ]]
  [[ "$output" == *"env_file_last_run_mtime=n/a"* ]]
  [[ "$output" == *"env_file_last_run_consistency=missing"* ]]
  [[ "$output" == *"watchtower_container=not_running"* ]]
  [[ "$output" == *"watchtower_container_exists=no"* ]]
  [[ "$output" == *"watchtower_container_created=n/a"* ]]
  [[ "$output" == *"watchtower_run_mode_effective_hint=n/a"* ]]
}
