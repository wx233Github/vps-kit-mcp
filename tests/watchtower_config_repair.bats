#!/usr/bin/env bats

@test "watchtower config repair keeps interval mode on positive intervals" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    warnings=0
    log_warn() { warnings=$((warnings + 1)); }

    WATCHTOWER_RUN_MODE="interval"
    WATCHTOWER_CONFIG_INTERVAL="300"
    WATCHTOWER_CONF_DEFAULT_INTERVAL="600"

    _repair_watchtower_loaded_config

    [ "$WATCHTOWER_CONFIG_INTERVAL" = "300" ]
    [ "$warnings" -eq 0 ]
  '
  [ "$status" -eq 0 ]
}

@test "watchtower config repair falls back invalid interval values in interval mode" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    warnings=0
    log_warn() { warnings=$((warnings + 1)); }

    WATCHTOWER_RUN_MODE="interval"
    WATCHTOWER_CONFIG_INTERVAL="0"
    WATCHTOWER_CONF_DEFAULT_INTERVAL="600"

    _repair_watchtower_loaded_config

    [ "$WATCHTOWER_CONFIG_INTERVAL" = "600" ]
    [ "$warnings" -eq 1 ]
  '
  [ "$status" -eq 0 ]
}

@test "watchtower config repair skips interval warning in aligned mode when interval is zero" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    warnings=0
    log_warn() { warnings=$((warnings + 1)); }

    WATCHTOWER_RUN_MODE="aligned"
    WATCHTOWER_CONFIG_INTERVAL="0"
    WATCHTOWER_SCHEDULE_CRON="0 0 */6 * * *"
    WATCHTOWER_CONF_DEFAULT_INTERVAL="600"

    _repair_watchtower_loaded_config

    [ "$WATCHTOWER_CONFIG_INTERVAL" = "0" ]
    [ "$WATCHTOWER_RUN_MODE" = "aligned" ]
    [ "$warnings" -eq 0 ]
  '
  [ "$status" -eq 0 ]
}

@test "watchtower config repair normalizes non-numeric interval placeholders in cron mode" {
  run bash -c '
    set -euo pipefail
    source /root/aa/vps-kit-mcp/tools/Watchtower.sh

    warnings=0
    log_warn() { warnings=$((warnings + 1)); }

    WATCHTOWER_RUN_MODE="cron"
    WATCHTOWER_CONFIG_INTERVAL="bad"
    WATCHTOWER_SCHEDULE_CRON="0 0 4 * * *"
    WATCHTOWER_CONF_DEFAULT_INTERVAL="600"

    _repair_watchtower_loaded_config

    [ "$WATCHTOWER_CONFIG_INTERVAL" = "0" ]
    [ "$WATCHTOWER_RUN_MODE" = "cron" ]
    [ "$warnings" -eq 0 ]
  '
  [ "$status" -eq 0 ]
}
