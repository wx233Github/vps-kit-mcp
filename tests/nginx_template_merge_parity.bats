#!/usr/bin/env bats
# Coverage Matrix
# - _template_merge_custom_config：append/replace 两种模式，且合并后统一过规范化
# - _template_cleanup_custom_config：all/ids 两种模式，且清理后统一过规范化
# - 影响预测与应用共用同一合并实现（本文件即守护该入口存在且行为一致）
#
# Fixture Conventions
# - sed '$d' nginx.sh > 临时 lib，子 shell 内 source
# - stub 规范化与块提取，聚焦合并语义

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.tpl.merge.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "append 模式保留既有块并追加 payload" {
  run bash -c '
    source "$1"
    _normalize_custom_config_text() { printf "%s" "$1"; }
    _extract_template_blocks_by_ids() { printf "%s" "KEEP"; }
    _template_merge_custom_config "CUR" "PAY" append id1
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "KEEP
PAY" ]
}

@test "replace 模式只保留 payload" {
  run bash -c '
    source "$1"
    _normalize_custom_config_text() { printf "%s" "$1"; }
    _extract_template_blocks_by_ids() { printf "%s" "KEEP"; }
    _template_merge_custom_config "CUR" "PAY" replace id1
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "PAY" ]
}

@test "append 模式无既有块时结果即 payload" {
  run bash -c '
    source "$1"
    _normalize_custom_config_text() { printf "%s" "$1"; }
    _extract_template_blocks_by_ids() { :; }
    _template_merge_custom_config "CUR" "PAY" append id1
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "PAY" ]
}

@test "合并结果统一经过规范化函数" {
  run bash -c '
    source "$1"
    _normalize_custom_config_text() { printf "%s" "$1" | tr "a-z" "A-Z"; }
    _extract_template_blocks_by_ids() { :; }
    _template_merge_custom_config "cur" "pay" replace id1
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "PAY" ]
}

@test "cleanup all 模式移除全部块并规范化" {
  run bash -c '
    source "$1"
    _normalize_custom_config_text() { printf "%s" "$1"; }
    _extract_all_template_blocks() { printf "%s" "REST"; }
    _template_cleanup_custom_config "CUR" all
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "REST" ]
}

@test "cleanup ids 模式按 ID 移除并规范化" {
  run bash -c '
    source "$1"
    _normalize_custom_config_text() { printf "%s" "$1"; }
    _extract_template_blocks_by_ids() { printf "ids=%s" "$1"; }
    _template_cleanup_custom_config "CUR" ids a b
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "ids=CUR" ]
}
