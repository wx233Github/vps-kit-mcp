#!/usr/bin/env bats
# Coverage Matrix
# - _nginx_upstream_meta: 取「Stable version」段的版本，不能被页面顶部的 Mainline 版带偏
# - _nginx_new_version_line: 同分支补丁 / 旧分支停维护 / 已是最新 / 未知版本 四种分支
#
# Fixture Conventions
# - curl 用固定 HTML 片段 stub，不依赖外网，也不依赖宿主 nginx。

setup() {
  SCRIPT_PATH="${BATS_TEST_DIRNAME%/tests}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.ver.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
  WORK_DIR="$(mktemp -d /tmp/nginx.ver.dir.XXXXXX)"
}

teardown() {
  rm -f "$LIB_PATH"
  rm -rf "$WORK_DIR"
}

@test "_nginx_upstream_meta: 取稳定版而不是页面第一个（主线）版本" {
  run bash -c '
    source "$1"
    curl() {
      printf "%s" "<html>Mainline version</h4>CHANGES nginx-1.31.8 <a>nginx/Windows-1.31.8</a>
Stable version</h4>CHANGES-1.30 nginx-1.30.6 <a>nginx/Windows-1.30.6</a>
Legacy versions</h4>CHANGES-1.28 nginx-1.28.3 CHANGES-1.26 nginx-1.26.3</html>"
    }
    NGINX_UPSTREAM_META_CACHE="$2" _nginx_upstream_meta
  ' _ "$LIB_PATH" "$WORK_DIR/meta.cache"
  [ "$status" -eq 0 ]
  [[ "$output" == 1.30.6$'\t'* ]]
  [[ "$output" == *"1.26"* ]]
}

@test "_nginx_new_version_line: 当前分支已停维护时给出升级建议" {
  run bash -c '
    source "$1"
    _nginx_upstream_meta() { printf "%s\t%s" 1.30.6 "1.30 1.28 1.26"; }
    _nginx_new_version_line 1.26.3
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.26 分支已停止维护"* ]]
  [[ "$output" == *"1.30.6"* ]]
}

@test "_nginx_new_version_line: 同分支补丁更新" {
  run bash -c '
    source "$1"
    _nginx_upstream_meta() { printf "%s\t%s" 1.30.6 "1.30 1.28 1.26"; }
    _nginx_new_version_line 1.30.5
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"稳定版补丁更新"* ]]
  [[ "$output" != *"已停止维护"* ]]
}

@test "_nginx_new_version_line: 已是最新或更高版本时不提示" {
  run bash -c '
    source "$1"
    _nginx_upstream_meta() { printf "%s\t%s" 1.30.6 "1.30 1.28 1.26"; }
    _nginx_new_version_line 1.30.6
    _nginx_new_version_line 1.31.8
    _nginx_new_version_line unknown
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_nginx_new_version_line: 取不到上游信息时静默" {
  run bash -c '
    source "$1"
    _nginx_upstream_meta() { :; }
    _nginx_new_version_line 1.26.3
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
