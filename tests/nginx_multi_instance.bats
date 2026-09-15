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
  chown nobody "$WORK_DIR/own" 2>/dev/null || chown 65534 "$WORK_DIR/own"
  chmod 700 "$WORK_DIR/own"
  run bash -c 'source "$1"; _path_writable_by_user "$2" nobody && echo YES || echo NO' _ "$LIB_PATH" "$WORK_DIR/own"
  [ "$status" -eq 0 ]
  [ "$output" = "YES" ]
}

@test "_path_writable_by_user: 他人所有且无组权限时不可写" {
  mkdir -p "$WORK_DIR/ro"
  chown root:root "$WORK_DIR/ro"
  chmod 700 "$WORK_DIR/ro"
  run bash -c 'source "$1"; _path_writable_by_user "$2" nobody && echo YES || echo NO' _ "$LIB_PATH" "$WORK_DIR/ro"
  [ "$status" -eq 0 ]
  [ "$output" = "NO" ]
}

@test "_path_writable_by_user: root 不受权限位限制" {
  mkdir -p "$WORK_DIR/rootro"
  chown root:root "$WORK_DIR/rootro"
  chmod 700 "$WORK_DIR/rootro"
  run bash -c 'source "$1"; _path_writable_by_user "$2" root && echo YES || echo NO' _ "$LIB_PATH" "$WORK_DIR/rootro"
  [ "$status" -eq 0 ]
  [ "$output" = "YES" ]
}

@test "_path_writable_by_user: 属组为附加组时可写（回归：旧版只查主组会误判）" {
  local gid
  gid=$(getent group bin | cut -d: -f3)
  [ -n "$gid" ] || skip "无 bin 组可供测试"
  mkdir -p "$WORK_DIR/grp"
  chown root:"$gid" "$WORK_DIR/grp"
  chmod 2770 "$WORK_DIR/grp"
  # stub：主组为 1，附加组含目录的属组
  run env TARGET_GID="$gid" bash -c '
    source "$1"
    id() { case "$1" in -u) printf "%s\n" 65534 ;; -G) printf "%s\n" "1 $TARGET_GID" ;; *) command id "$@" ;; esac; }
    _path_writable_by_user "$2" nobody && echo YES || echo NO
  ' _ "$LIB_PATH" "$WORK_DIR/grp"
  [ "$status" -eq 0 ]
  [ "$output" = "YES" ]
}

@test "_path_writable_by_user: 属组但用户非其成员时不可写" {
  local gid
  gid=$(getent group bin | cut -d: -f3)
  [ -n "$gid" ] || skip "无 bin 组可供测试"
  mkdir -p "$WORK_DIR/notmember"
  chown root:"$gid" "$WORK_DIR/notmember"
  chmod 2770 "$WORK_DIR/notmember"
  run bash -c '
    source "$1"
    id() { case "$1" in -u) printf "%s\n" 65534 ;; -G) printf "%s\n" "1" ;; *) command id "$@" ;; esac; }
    _path_writable_by_user "$2" nobody && echo YES || echo NO
  ' _ "$LIB_PATH" "$WORK_DIR/notmember"
  [ "$status" -eq 0 ]
  [ "$output" = "NO" ]
}

@test "_path_writable_by_user: setgid 位不影响组写判定" {
  local gid
  gid=$(getent group bin | cut -d: -f3)
  [ -n "$gid" ] || skip "无 bin 组可供测试"
  mkdir -p "$WORK_DIR/setgid"
  chown root:"$gid" "$WORK_DIR/setgid"
  chmod 0770 "$WORK_DIR/setgid"
  run env TARGET_GID="$gid" bash -c '
    source "$1"
    id() { case "$1" in -u) printf "%s\n" 65534 ;; -G) printf "%s\n" "1 $TARGET_GID" ;; *) command id "$@" ;; esac; }
    _path_writable_by_user "$2" nobody && echo YES || echo NO
  ' _ "$LIB_PATH" "$WORK_DIR/setgid"
  [ "$status" -eq 0 ]
  [ "$output" = "YES" ]
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

@test "_nginx_shared_group_name: 默认与可通过环境变量覆盖" {
  run bash -c 'source "$1"; _nginx_shared_group_name' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "nginx-shared" ]
  run env NGINX_SHARED_GROUP=my-grp bash -c 'source "$1"; _nginx_shared_group_name' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "my-grp" ]
}

@test "_nginx_sysbin: 能找到不在 PATH 上的系统命令（回归：脚本 PATH 不含 /usr/sbin）" {
  run bash -c '
    export PATH="/usr/local/bin:/usr/bin:/bin"
    source "$1"
    bin=$(_nginx_sysbin groupadd 2>/dev/null || true)
    if [ -z "$bin" ]; then echo MISSING; else
      case "$bin" in /*) echo ABSOLUTE ;; *) echo RELATIVE ;; esac
    fi
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "ABSOLUTE" ]
}

@test "_fix_nginx_temp_path_conflicts: 目标目录不在 safe roots 时不得被拦（回归）" {
  # 旧版额外调用 _require_safe_path，而 SAFE_PATH_ROOTS 不含 /var/lib/nginx，
  # 导致修复静默无效。这里断言授权判定只用 _nginx_temp_path_allowed。
  run bash -c '
    source "$1"
    # SAFE_PATH_ROOTS 确实不包含 /var/lib/nginx —— 正是不能依赖它的原因
    for root in "${SAFE_PATH_ROOTS[@]}"; do
      [ "$root" = "/var/lib/nginx" ] && { echo CONTAINS; exit 0; }
    done
    echo NOT_CONTAINS
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "NOT_CONTAINS" ]
}

@test "多实例但双方都可写时不报异常（回归：旧版会持续误报）" {
  mkdir -p "$WORK_DIR/two"
  chmod 2777 "$WORK_DIR/two"
  run bash -c '
    source "$1"
    _list_nginx_master_pids() { printf "%s\n%s\n" 1234 5678; }
    _read_proc_cmdline() { :; }
    _extract_nginx_conf_from_master_cmd() { printf "%s\n" /etc/nginx/nginx.conf; }
    _get_nginx_pid_file_from_conf() { printf "%s\n" /tmp/a.pid; }
    _nginx_effective_temp_paths() { printf "%s\t%s\t%s\n" client_body "$2" explicit; }
    _nginx_effective_worker_user() {
      case "$1" in 1234) printf "%s\n" nobody ;; *) printf "%s\n" daemon ;; esac
    }
    _nginx_multi_instance_conflicts
  ' _ "$LIB_PATH" "$WORK_DIR/two"
  [ "$status" -eq 0 ]
  [[ "$output" != 异常* ]]
  [[ "$output" != *"无权写入"* ]]
}

@test "集成：修复走 chgrp+2770 而不是 chown（根治而非治标）" {
  # 需要一个「有真实成员」的组，才能让入组后的可写性判定成立
  local grp=""
  grp=$(getent group | awk -F: '$4!=""{print $1; exit}')
  [ -n "$grp" ] || skip "无带成员的组可供测试"
  local member=""
  member=$(getent group "$grp" | cut -d: -f4 | cut -d, -f1)
  [ -n "$member" ] || skip "组 $grp 无成员"

  mkdir -p "$WORK_DIR/tp"
  chown root:root "$WORK_DIR/tp"
  chmod 700 "$WORK_DIR/tp"
  {
    echo "http {"
    echo "    client_body_temp_path $WORK_DIR/tp;"
    echo "}"
  } >"$WORK_DIR/n.conf"

  run env TARGET_DIR="$WORK_DIR/tp" TARGET_CONF="$WORK_DIR/n.conf"       SHARED_GRP="$grp" MEMBER="$member" bash -c '
    source "$1"
    systemctl() { :; }
    _nginx_sysbin() { printf "%s\n" /bin/true; }   # groupadd/usermod 假成功
    _list_nginx_master_pids() { printf "%s\n" 1234; }
    _read_proc_cmdline() { :; }
    _extract_nginx_conf_from_master_cmd() { printf "%s\n" "$TARGET_CONF"; }
    _nginx_effective_worker_user() { printf "%s\n" "$MEMBER"; }
    _get_nginx_pid_file_from_conf() { printf "%s\n" /tmp/a.pid; }
    _nginx_effective_temp_paths() { printf "%s\t%s\t%s\n" client_body "$TARGET_DIR" explicit; }
    NGINX_SHARED_GROUP="$SHARED_GRP" _fix_nginx_temp_path_conflicts >/dev/null 2>&1
    echo "rc=$?"
    stat -c "%U:%G:%a" "$TARGET_DIR"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0"* ]]
  # 属组切到共享组 + 组写位 + setgid；属主不被改动
  [[ "$output" == *"root:$grp:2770"* ]]
}

@test "集成：修复后检测不再报异常（闭环）" {
  local grp=""
  grp=$(getent group | awk -F: '$4!=""{print $1; exit}')
  [ -n "$grp" ] || skip "无带成员的组可供测试"
  local member=""
  member=$(getent group "$grp" | cut -d: -f4 | cut -d, -f1)
  [ -n "$member" ] || skip "组 $grp 无成员"

  mkdir -p "$WORK_DIR/tp2"
  chown root:root "$WORK_DIR/tp2"
  chmod 700 "$WORK_DIR/tp2"
  {
    echo "http {"
    echo "    client_body_temp_path $WORK_DIR/tp2;"
    echo "}"
  } >"$WORK_DIR/n2.conf"

  run env TARGET_DIR="$WORK_DIR/tp2" TARGET_CONF="$WORK_DIR/n2.conf"       SHARED_GRP="$grp" MEMBER="$member" bash -c '
    source "$1"
    systemctl() { :; }
    _nginx_sysbin() { printf "%s\n" /bin/true; }
    _list_nginx_master_pids() { printf "%s\n" 1234; }
    _read_proc_cmdline() { :; }
    _extract_nginx_conf_from_master_cmd() { printf "%s\n" "$TARGET_CONF"; }
    _nginx_effective_worker_user() { printf "%s\n" "$MEMBER"; }
    _get_nginx_pid_file_from_conf() { printf "%s\n" /tmp/b.pid; }
    _nginx_effective_temp_paths() { printf "%s\t%s\t%s\n" client_body "$TARGET_DIR" explicit; }
    NGINX_SHARED_GROUP="$SHARED_GRP" _fix_nginx_temp_path_conflicts >/dev/null 2>&1
    NGINX_SHARED_GROUP="$SHARED_GRP" _nginx_multi_instance_conflicts
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" != 异常* ]]
  [[ "$output" != *"无权写入"* ]]
}
