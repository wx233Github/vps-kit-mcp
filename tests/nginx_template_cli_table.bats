#!/usr/bin/env bats
# Coverage Matrix
# - _TM_FLAG_TABLE 是参数解析、参数校验与用法文本的唯一来源
# - tm_validate_args 拒绝未知参数、拒绝缺失参数值
# - tm_print_usage 输出覆盖所有带说明的模板参数

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
}

@test "未知参数被 tm_validate_args 拒绝" {
  run bash -c '
    source "$1/lib/template_cli.sh"
    log_message() { printf "%s\n" "$2"; }
    tm_parse_args --bogus-flag
    tm_validate_args --bogus-flag
    printf "RC:%s\n" "$?"
  ' bash "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"未知参数: --bogus-flag"* ]]
  [[ "$output" == *"RC:1"* ]]
}

@test "需要取值的参数缺失时报缺少参数值" {
  run bash -c '
    source "$1/lib/template_cli.sh"
    log_message() { printf "%s\n" "$2"; }
    tm_parse_args --template-mode
    tm_validate_args --template-mode
    printf "RC:%s\n" "$?"
  ' bash "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"缺少参数值"* ]]
  [[ "$output" == *"RC:1"* ]]
}

@test "参数表与用法文本、校验清单同源" {
  run bash -c '
    source "$1/lib/template_cli.sh"
    log_message() { :; }
    for row in "${_TM_FLAG_TABLE[@]}"; do
      IFS="|" read -r flag var def kind use desc <<<"$row"
      first="${flag%%,*}"
      if [ -n "$use" ]; then
        grep -q -- "$first" <(tm_print_usage) || { printf "usage-missing:%s\n" "$first"; exit 1; }
      fi
      case "$kind" in
        bool|set|value) ;;
        *) printf "bad-kind:%s\n" "$kind"; exit 1 ;;
      esac
      [ -n "$var" ] || { printf "no-var:%s\n" "$first"; exit 1; }
    done
    printf "OK\n"
  ' bash "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "bool 与 value 两类参数解析结果符合预期" {
  run bash -c '
    source "$1/lib/template_cli.sh"
    log_message() { :; }
    tm_parse_args --template-mode custom --template-domain a.example.com --template-ids hsts --template-apply-mode replace --template-parallelism 4 --json --fail-fast
    printf "%s|%s|%s|%s|%s|%s\n" "$TEMPLATE_MODE" "$TEMPLATE_DOMAIN" "$TEMPLATE_IDS" "$TEMPLATE_APPLY_MODE" "$TEMPLATE_PARALLELISM" "$TEMPLATE_OUTPUT_JSON"
  ' bash "$REPO_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "custom|a.example.com|hsts|replace|4|true" ]
}
