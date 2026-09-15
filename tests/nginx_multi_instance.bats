#!/usr/bin/env bats
# Coverage Matrix
# - _path_writable_by_user: 属主/属组写位判定（只读临时目录 -> 不可写）
# - _nginx_effective_temp_paths: 未配置时回退编译默认值
# - _nginx_multi_instance_conflicts: 单实例 -> 正常；共用 pid -> 需关注；写不通 -> 异常
#
# Fixture Conventions
# - 全部通过 stub 覆盖 _list_nginx_master_pids / _nginx_bin_or_empty，
#   不依赖宿主真实 nginx 进程与配置。

setup() {
  SCRIPT_PATH="${BATS_TEST_DIRNAME%/tests}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.multi.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
  WORK_DIR="$(mktemp -d /tmp/nginx.multi.dir.XXXXXX)"
}

teardown() {
  rm -f "$LIB_PATH"
  rm -rf "$WORK_DIR"
}

@test "_path_writable_by_user: 属主带写位时可写" {
  mkdir -p "$WORK_DIR/own"
  chmod 700 "$WORK_DIR/own"
  run bash -c 'source "$1"; _path_writable_by_user "$2" "$(id -un)" && echo YES || echo NO' _ "$LIB_PATH" "$WORK_DIR/own"
  [ "$status" -eq 0 ]
  [ "$output" = "YES" ]
}

@test "_path_writable_by_user: 只读目录不可写" {
  mkdir -p "$WORK_DIR/ro"
  chmod 500 "$WORK_DIR/ro"
  run bash -c 'source "$1"; _path_writable_by_user "$2" "$(id -un)" && echo YES || echo NO' _ "$LIB_PATH" "$WORK_DIR/ro"
  [ "$status" -eq 0 ]
  [ "$output" = "NO" ]
}

@test "_path_writable_by_user: 目录不存在返回不可写" {
  run bash -c 'source "$1"; _path_writable_by_user "$2/nope" root && echo YES || echo NO' _ "$LIB_PATH" "$WORK_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "NO" ]
}

@test "_nginx_effective_temp_paths: 无显式配置时回退编译默认值" {
  run bash -c '
    source "$1"
    _nginx_compiled_temp_paths() { printf "%s\t%s\n" client_body /var/lib/nginx/body; }
    _nginx_effective_temp_paths /nonexistent.conf
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/var/lib/nginx/body"* ]]
  [[ "$output" == *"compiled"* ]]
}

@test "_nginx_effective_temp_paths: 显式配置覆盖编译默认值" {
  cat >"$WORK_DIR/n.conf" <<EOF
http {
    client_body_temp_path $WORK_DIR/own;
}
EOF
  run bash -c '
    source "$1"
    _nginx_compiled_temp_paths() { printf "%s\t%s\n" client_body /var/lib/nginx/body; }
    _nginx_effective_temp_paths "$2"
  ' _ "$LIB_PATH" "$WORK_DIR/n.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$WORK_DIR/own"* ]]
  [[ "$output" == *"explicit"* ]]
}

@test "单实例时判定为正常" {
  run bash -c '
    source "$1"
    _list_nginx_master_pids() { printf "%s\n" 1234; }
    _nginx_effective_worker_user() { printf "%s\n" root; }
    _get_nginx_pid_file_from_conf() { printf "%s\n" /tmp/a.pid; }
    _nginx_effective_temp_paths() { :; }
    _nginx_multi_instance_conflicts
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == 正常* ]]
  [ "${output%%$'\t'*}" = "正常" ]
}

@test "多实例共用 pid 文件时判定为需关注" {
  run bash -c '
    source "$1"
    _list_nginx_master_pids() { printf "%s\n%s\n" 1234 5678; }
    _nginx_effective_worker_user() { printf "%s\n" www-data; }
    _get_nginx_pid_file_from_conf() { printf "%s\n" /run/nginx.pid; }
    _nginx_effective_temp_paths() { :; }
    _nginx_multi_instance_conflicts
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == 需关注* ]]
  [[ "$output" == *"/run/nginx.pid"* ]]
}

@test "worker 用户写不进临时目录时判定为异常" {
  mkdir -p "$WORK_DIR/body"
  chmod 500 "$WORK_DIR/body"
  # stub 的 $2 会收到调用方的 $conf，因此目录路径通过环境变量注入 stub 源码
  export TARGET_DIR="$WORK_DIR/body"
  run bash -c '
    source "$1"
    _list_nginx_master_pids() { printf "%s\n" 1234; }
    _nginx_effective_worker_user() { printf "%s\n" nobody; }
    _get_nginx_pid_file_from_conf() { printf "%s\n" /tmp/a.pid; }
    _nginx_effective_temp_paths() { printf "%s\t%s\t%s\n" client_body "$TARGET_DIR" explicit; }
    _nginx_multi_instance_conflicts
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"无权写入"* ]]
}

@test "_nginx_multi_instance_line: 正常时输出为空" {
  run bash -c '
    source "$1"
    _nginx_multi_instance_conflicts() { printf "%s\t%s\n" 正常 ""; }
    _nginx_multi_instance_line
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_nginx_multi_instance_line: 异常时输出告警" {
  run bash -c '
    source "$1"
    _nginx_multi_instance_conflicts() { printf "%s\t%s\n" 异常 "测试冲突"; }
    _nginx_multi_instance_line
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"多实例冲突"* ]]
  [[ "$output" == *"测试冲突"* ]]
}

@test "_nginx_temp_path_allowed: 接受主配置声明的 temp_path" {
  mkdir -p "$WORK_DIR/body"
  cat >"$WORK_DIR/n.conf" <<EOF
http {
    client_body_temp_path $WORK_DIR/body;
}
EOF
  export TARGET_DIR="$WORK_DIR/body"
  export TARGET_CONF="$WORK_DIR/n.conf"
  run bash -c '
    source "$1"
    _list_nginx_master_pids() { printf "%s\n" 1234; }
    _read_proc_cmdline() { :; }
    _extract_nginx_conf_from_master_cmd() { printf "%s\n" "$TARGET_CONF"; }
    _nginx_compiled_temp_paths() { :; }
    _nginx_temp_path_allowed "$TARGET_DIR" && echo YES || echo NO
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "YES" ]
}

@test "_nginx_temp_path_allowed: 拒绝未声明的路径（不沿 SAFE_PATH_ROOTS 放宽）" {
  mkdir -p "$WORK_DIR/evil"
  run bash -c '
    source "$1"
    _list_nginx_master_pids() { printf "%s\n" 1234; }
    _read_proc_cmdline() { :; }
    _extract_nginx_conf_from_master_cmd() { printf "%s\n" /etc/nginx/nginx.conf; }
    _nginx_compiled_temp_paths() { printf "%s\t%s\n" client_body /var/lib/nginx/body; }
    _nginx_temp_path_allowed "$2" && echo YES || echo NO
  ' _ "$LIB_PATH" "$WORK_DIR/evil"
  [ "$status" -eq 0 ]
  [ "$output" = "NO" ]
}

@test "_nginx_temp_path_allowed: 拒绝含 .. 的路径" {
  run bash -c '
    source "$1"
    _list_nginx_master_pids() { printf "%s\n" 1234; }
    _read_proc_cmdline() { :; }
    _extract_nginx_conf_from_master_cmd() { printf "%s\n" /etc/nginx/nginx.conf; }
    _nginx_compiled_temp_paths() { :; }
    _nginx_temp_path_allowed "/etc/nginx/../../etc/shadow" && echo YES || echo NO
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "NO" ]
}

