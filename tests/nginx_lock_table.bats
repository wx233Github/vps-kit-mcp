#!/usr/bin/env bats
# Coverage Matrix
# - 锁包装由单一名字表驱动：acquire_<name>_lock / release_<name>_lock
# - 抢占同一锁时第二次获取失败（flock -n）
# - cleanup 按名字表释放全部锁文件
#
# Fixture Conventions
# - sed '$d' nginx.sh > 临时 lib，子 shell 内 source
# - LOCK_FILE_* 指向临时目录，避免写 /var/lock

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.lock.table.lib.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "acquire_project_lock 写入 pid 并设置 FD 与 owner" {
  run bash -c '
    source "$1"
    d=$(mktemp -d)
    LOCK_FILE_PROJECT="$d/p.lock"
    acquire_project_lock || exit 1
    [ "$(cat "$LOCK_FILE_PROJECT")" = "$$" ] || exit 2
    [[ "$LOCK_FD_PROJECT" =~ ^[0-9]+$ ]] || exit 3
    [ "$LOCK_OWNER_PID_PROJECT" = "$$" ] || exit 4
    release_project_lock || exit 5
    [ ! -f "$LOCK_FILE_PROJECT" ] || exit 6
    [ -z "$LOCK_OWNER_PID_PROJECT" ] || exit 7
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "同一锁被占用时第二次获取失败" {
  run bash -c '
    source "$1"
    d=$(mktemp -d)
    LOCK_FILE_PROJECT="$d/p.lock"
    acquire_project_lock || exit 1
    ( acquire_project_lock ) && exit 2
    exit 0
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "八个具名锁可依次获取且 owner 变量全部就位" {
  run bash -c '
    source "$1"
    d=$(mktemp -d)
    for n in HTTP TCP CERT PROJECT LOGROTATE CRON CF WAL; do
      eval "LOCK_FILE_$n=\"$d/$n.lock\""
    done
    acquire_http_lock && acquire_tcp_lock && acquire_cert_lock && acquire_project_lock || exit 1
    acquire_logrotate_lock && acquire_cron_lock && acquire_cf_lock && acquire_wal_lock || exit 2
    for n in HTTP TCP CERT PROJECT LOGROTATE CRON CF WAL; do
      eval "owner=\${LOCK_OWNER_PID_$n:-}"
      [ "$owner" = "$$" ] || exit 3
    done
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "cleanup 释放名字表中的全部锁文件" {
  run bash -c '
    source "$1"
    d=$(mktemp -d)
    for n in HTTP TCP CERT PROJECT LOGROTATE CRON CF WAL; do
      eval "LOCK_FILE_$n=\"$d/$n.lock\""
    done
    acquire_http_lock; acquire_tcp_lock; acquire_cert_lock; acquire_project_lock
    acquire_logrotate_lock; acquire_cron_lock; acquire_cf_lock; acquire_wal_lock
    cleanup >/dev/null 2>&1
    for f in "$d"/*.lock; do
      [ ! -e "$f" ] || exit 5
    done
  ' "$SCRIPT_PATH" "$LIB_PATH"
  [ "$status" -eq 0 ]
}
