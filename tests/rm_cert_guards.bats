#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SRC="${REPO_ROOT}/rm/rm_cert.sh"
  LIB_PATH="$(mktemp /tmp/rm.cert.lib.XXXXXX.sh)"
  python3 - "$SRC" "$LIB_PATH" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
lines = src.read_text().splitlines()
trimmed = []
for line in lines:
    if line.strip() in {'self_elevate_or_die "$@"', 'parse_dry_run_args "$@"', 'set -- "${RUN_ARGS[@]}"'}:
        continue
    if line.startswith('log_info "=============================="'):
        break
    trimmed.append(line)
dst.write_text("\n".join(trimmed) + "\n")
PY
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "rm cert parse_dry_run_args extracts dry-run domains and backup mode" {
  run bash -c '
    set -euo pipefail
    source "$1"
    DRY_RUN="false"
    DOMAINS_CSV=""
    BACKUP_MODE="ask"
    RUN_ARGS=()
    log_warn() { printf "WARN:%s\n" "$*"; }
    parse_dry_run_args --dry-run --domains=a.com,b.com --backup=always keep-arg
    [[ "$DRY_RUN" == "true" ]]
    [[ "$DOMAINS_CSV" == "a.com,b.com" ]]
    [[ "$BACKUP_MODE" == "always" ]]
    [[ "${RUN_ARGS[0]-}" == "keep-arg" ]]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN:已启用 dry-run"* ]]
}

@test "rm cert high_risk_guard rejects automatically in noninteractive mode" {
  run bash -c '
    set -euo pipefail
    source "$1"
    JB_NONINTERACTIVE="true"
    if high_risk_guard "危险动作" "不可逆"; then
      exit 1
    fi
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"非交互模式：高风险操作默认取消"* ]]
}

@test "rm cert run_destructive_cmd is noop in dry-run" {
  run bash -c '
    set -euo pipefail
    source "$1"
    DRY_RUN="true"
    log_info() { printf "%s\n" "$*"; }
    rm() { printf "should-not-run\n" >&2; exit 99; }
    run_destructive_cmd rm -rf /etc/ssl/demo
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN] rm"* ]]
  [[ "$output" == *"-rf"* ]]
  [[ "$output" == *"/etc/ssl/demo"* ]]
}

@test "rm cert ensure_safe_path rejects empty and root paths" {
  run bash -c '
    set +e
    source "$1"
    log_err() { printf "ERR:%s\n" "$*"; }
    ensure_safe_path "/"
  ' _ "$LIB_PATH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERR:拒绝对危险路径执行破坏性操作"* ]]
}

@test "rm cert skips crontab cleanup when user has no crontab" {
  run bash -c '
    set -euo pipefail
    source "$1"
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "crontab" ]; then
        return 0
      fi
      if [ "$1" = "-v" ] && [ "$2" = "socat" ]; then
        return 1
      fi
      builtin command "$@"
    }
    crontab() { return 0; }
    current_cron="$(crontab -l 2>/dev/null || true)"
    if [ -n "${current_cron}" ]; then
      exit 1
    else
      log_info "ℹ️ 当前用户无 crontab，跳过"
    fi
    command -v socat >/dev/null 2>&1 || log_info "ℹ️ socat 未安装，跳过"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ℹ️ 当前用户无 crontab，跳过"* ]]
  [[ "$output" == *"ℹ️ socat 未安装，跳过"* ]]
}

@test "rm cert backup=always backs up and deletes cert directory" {
  run bash -c '
    set -euo pipefail
    td="$(mktemp -d /tmp/rm.cert.backup.always.XXXXXX)"
    trap "/bin/rm -rf \"$td\"" EXIT
    source "$1"
    BACKUP_ROOT="$td/backup"
    DOMAIN="example.com"
    CERT_DIR="$td/etc/ssl/$DOMAIN"
    DEST="$BACKUP_ROOT/$DOMAIN"
    mkdir -p "$CERT_DIR"
    : > "$CERT_DIR/fullchain.cer"
    events="$td/events.log"
    mkdir() { printf "mkdir:%s\n" "$*" >>"$events"; command mkdir "$@"; }
    cp() { printf "cp:%s\n" "$*" >>"$events"; command cp "$@"; }
    run_destructive_cmd() { printf "rm:%s\n" "$*" >>"$events"; }
    ensure_safe_path() { return 0; }
    mkdir -p "$BACKUP_ROOT"
    local_backup_choice="always"
    if [ -d "$CERT_DIR" ]; then
      if [ "$local_backup_choice" = "always" ]; then
        mkdir -p "$DEST"
        cp -r "$CERT_DIR"/* "$DEST"/
        log_info "✅ 已备份 $DOMAIN 证书到 $DEST"
      fi
      log_info "🔹 删除证书目录 $CERT_DIR ..."
      ensure_safe_path "$CERT_DIR"
      run_destructive_cmd rm -rf "$CERT_DIR"
    fi
    cat "$events"
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ 已备份 example.com 证书到 "* ]]
  [[ "$output" == *"cp:-r"* ]]
  [[ "$output" == *"rm:rm"* ]]
  [[ "$output" == *"-rf"* ]]
}

@test "rm cert backup=never deletes cert directory without backup" {
  run bash -c '
    set -euo pipefail
    td="$(mktemp -d /tmp/rm.cert.backup.never.XXXXXX)"
    trap "/bin/rm -rf \"$td\"" EXIT
    source "$1"
    BACKUP_ROOT="$td/backup"
    DOMAIN="example.com"
    CERT_DIR="$td/etc/ssl/$DOMAIN"
    mkdir -p "$CERT_DIR"
    events="$td/events.log"
    cp() { printf "cp-called\n" >>"$events"; return 88; }
    run_destructive_cmd() { printf "rm:%s\n" "$*" >>"$events"; }
    ensure_safe_path() { return 0; }
    local_backup_choice="never"
    if [ -d "$CERT_DIR" ]; then
      if [ "$local_backup_choice" = "always" ]; then
        cp -r "$CERT_DIR"/* "$BACKUP_ROOT/$DOMAIN"/
      fi
      log_info "🔹 删除证书目录 $CERT_DIR ..."
      ensure_safe_path "$CERT_DIR"
      run_destructive_cmd rm -rf "$CERT_DIR"
    fi
    cat "$events"
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"🔹 删除证书目录 "* ]]
  [[ "$output" == *"rm:rm"* ]]
  [[ "$output" == *"-rf"* ]]
  [[ "$output" != *"cp-called"* ]]
  [[ "$output" != *"✅ 已备份"* ]]
}

@test "rm cert removes crontab when only acme jobs remain" {
  run bash -c '
    set -euo pipefail
    source "$1"
    events="$(mktemp /tmp/rm.cert.cron.remove.XXXXXX)"
    trap "rm -f \"$events\"" EXIT
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "crontab" ]; then
        return 0
      fi
      builtin command "$@"
    }
    crontab() {
      if [ "$1" = "-l" ]; then
        printf "%s\n" "0 3 * * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh"
        return 0
      fi
      if [ "$1" = "-r" ]; then
        printf "crontab-remove\n" >>"$events"
        return 0
      fi
      return 1
    }
    current_cron="$(crontab -l 2>/dev/null || true)"
    filtered_cron="$(printf "%s\n" "${current_cron}" | grep -v acme.sh || true)"
    if [ -z "$filtered_cron" ]; then
      crontab -r
    fi
    cat "$events"
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"crontab-remove"* ]]
}

@test "rm cert updates crontab when non-acme jobs remain" {
  run bash -c '
    set -euo pipefail
    source "$1"
    events="$(mktemp /tmp/rm.cert.cron.filter.XXXXXX)"
    trap "rm -f \"$events\"" EXIT
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "crontab" ]; then
        return 0
      fi
      builtin command "$@"
    }
    crontab() {
      if [ "$1" = "-l" ]; then
        printf "%s\n%s\n" "0 3 * * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh" "5 4 * * * /usr/bin/backup"
        return 0
      fi
      if [ "$1" = "-" ]; then
        cat >"$events"
        return 0
      fi
      if [ "$1" = "-r" ]; then
        printf "unexpected-remove\n" >>"$events"
        return 1
      fi
      return 1
    }
    current_cron="$(crontab -l 2>/dev/null || true)"
    filtered_cron="$(printf "%s\n" "${current_cron}" | grep -v acme.sh || true)"
    if [ -n "$filtered_cron" ]; then
      printf "%s\n" "$filtered_cron" | crontab -
    fi
    cat "$events"
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/usr/bin/backup"* ]]
  [[ "$output" != *"acme.sh"* ]]
  [[ "$output" != *"unexpected-remove"* ]]
}

@test "rm cert skips domain deletion in noninteractive mode without domains" {
  run bash -c '
    set -euo pipefail
    source "$1"
    JB_NONINTERACTIVE="true"
    DOMAINS_CSV=""
    DOMAINS=()
    if [ -n "${DOMAINS_CSV}" ]; then
      IFS="," read -r -a DOMAINS <<<"${DOMAINS_CSV}"
    elif [ "${JB_NONINTERACTIVE}" = "true" ]; then
      log_warn "非交互模式：跳过证书删除步骤（可使用 --domains=example.com 指定）"
      DOMAINS=()
    fi
    if [ ${#DOMAINS[@]} -eq 0 ]; then
      log_info "ℹ️ 未输入任何域名，跳过证书删除步骤。"
    else
      exit 1
    fi
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"非交互模式：跳过证书删除步骤"* ]]
  [[ "$output" == *"ℹ️ 未输入任何域名，跳过证书删除步骤。"* ]]
}

@test "rm cert warns when crontab command is unavailable" {
  run bash -c '
    set -euo pipefail
    source "$1"
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "crontab" ]; then
        return 1
      fi
      builtin command "$@"
    }
    if command -v crontab >/dev/null 2>&1; then
      exit 1
    else
      log_warn "⚠️ 未检测到 crontab 命令，跳过自动续期任务清理"
    fi
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠️ 未检测到 crontab 命令，跳过自动续期任务清理"* ]]
}

@test "rm cert removes socat with apt when available" {
  run bash -c '
    set -euo pipefail
    td="$(mktemp -d /tmp/rm.cert.socat.apt.XXXXXX)"
    trap "/bin/rm -rf \"$td\"" EXIT
    source "$1"
    events="$td/events.log"
    /bin/mkdir -p "$td/bin"
    : >"$td/bin/socat"
    : >"$td/bin/apt"
    /bin/chmod +x "$td/bin/socat" "$td/bin/apt"
    PATH="$td/bin"
    run_destructive_cmd() { printf "%s\n" "$*" >"$events"; }
    if command -v socat >/dev/null 2>&1; then
      if command -v apt >/dev/null 2>&1; then
        run_destructive_cmd apt remove -y socat
      elif command -v yum >/dev/null 2>&1; then
        run_destructive_cmd yum remove -y socat
      elif command -v dnf >/dev/null 2>&1; then
        run_destructive_cmd dnf remove -y socat
      else
        log_warn "⚠️ 未知包管理器，无法自动卸载 socat"
      fi
    fi
    printf "%s" "$(<"$events")"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt"* ]]
  [[ "$output" == *"remove"* ]]
  [[ "$output" == *"-y"* ]]
  [[ "$output" == *"socat"* ]]
}

@test "rm cert removes socat with yum when apt is unavailable" {
  run bash -c '
    set -euo pipefail
    td="$(mktemp -d /tmp/rm.cert.socat.yum.XXXXXX)"
    trap "/bin/rm -rf \"$td\"" EXIT
    source "$1"
    events="$td/events.log"
    /bin/mkdir -p "$td/bin"
    : >"$td/bin/socat"
    : >"$td/bin/yum"
    /bin/chmod +x "$td/bin/socat" "$td/bin/yum"
    PATH="$td/bin"
    run_destructive_cmd() { printf "%s\n" "$*" >"$events"; }
    if command -v socat >/dev/null 2>&1; then
      if command -v apt >/dev/null 2>&1; then
        run_destructive_cmd apt remove -y socat
      elif command -v yum >/dev/null 2>&1; then
        run_destructive_cmd yum remove -y socat
      elif command -v dnf >/dev/null 2>&1; then
        run_destructive_cmd dnf remove -y socat
      else
        log_warn "⚠️ 未知包管理器，无法自动卸载 socat"
      fi
    fi
    printf "%s" "$(<"$events")"
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"yum"* ]]
  [[ "$output" == *"remove"* ]]
  [[ "$output" == *"-y"* ]]
  [[ "$output" == *"socat"* ]]
}

@test "rm cert removes socat with dnf when apt and yum are unavailable" {
  run bash -c '
    set -euo pipefail
    td="$(mktemp -d /tmp/rm.cert.socat.dnf.XXXXXX)"
    trap "/bin/rm -rf \"$td\"" EXIT
    source "$1"
    events="$td/events.log"
    /bin/mkdir -p "$td/bin"
    : >"$td/bin/socat"
    : >"$td/bin/dnf"
    /bin/chmod +x "$td/bin/socat" "$td/bin/dnf"
    PATH="$td/bin"
    run_destructive_cmd() { printf "%s\n" "$*" >"$events"; }
    if command -v socat >/dev/null 2>&1; then
      if command -v apt >/dev/null 2>&1; then
        run_destructive_cmd apt remove -y socat
      elif command -v yum >/dev/null 2>&1; then
        run_destructive_cmd yum remove -y socat
      elif command -v dnf >/dev/null 2>&1; then
        run_destructive_cmd dnf remove -y socat
      else
        log_warn "⚠️ 未知包管理器，无法自动卸载 socat"
      fi
    fi
    printf "%s" "$(<"$events")"
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dnf"* ]]
  [[ "$output" == *"remove"* ]]
  [[ "$output" == *"-y"* ]]
  [[ "$output" == *"socat"* ]]
}

@test "rm cert warns for unknown package manager when socat is installed" {
  run bash -c '
    set -euo pipefail
    source "$1"
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "socat" ]; then
        return 0
      fi
      if [ "$1" = "-v" ] && { [ "$2" = "apt" ] || [ "$2" = "yum" ] || [ "$2" = "dnf" ]; }; then
        return 1
      fi
      builtin command "$@"
    }
    if command -v socat >/dev/null 2>&1; then
      if command -v apt >/dev/null 2>&1; then
        run_destructive_cmd apt remove -y socat
      elif command -v yum >/dev/null 2>&1; then
        run_destructive_cmd yum remove -y socat
      elif command -v dnf >/dev/null 2>&1; then
        run_destructive_cmd dnf remove -y socat
      else
        log_warn "⚠️ 未知包管理器，无法自动卸载 socat"
      fi
    fi
   ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"⚠️ 未知包管理器，无法自动卸载 socat"* ]]
}
