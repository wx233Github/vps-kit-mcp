#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SRC="${REPO_ROOT}/rm/install.sh"
  LIB_PATH="$(mktemp /tmp/rm.install.lib.XXXXXX.sh)"
  python3 - "$SRC" "$LIB_PATH" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
lines = src.read_text().splitlines()
trimmed = []
for line in lines:
    if line.strip() in {'self_elevate_or_die "$@"', 'parse_cli_flags "$@"', 'main_menu'}:
        continue
    trimmed.append(line)
dst.write_text("\n".join(trimmed) + "\n")
PY
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "rm install parse_cli_flags enables download-only and custom base url" {
  run bash -c '
    set -euo pipefail
    source "$1"
    DOWNLOAD_ONLY="false"
    BASE_URL="https://raw.githubusercontent.com/wx233Github/vps-kit-mcp/main"
    parse_cli_flags --download-only --base-url=https://mirror.example.com/repo ignored
    [[ "$DOWNLOAD_ONLY" == "true" ]]
    [[ "$BASE_URL" == "https://mirror.example.com/repo" ]]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "rm install download prefers wget and saves basename" {
  run bash -c '
    set -euo pipefail
    td="$(mktemp -d /tmp/rm.install.download.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT
    cd "$td"
    source "$1"
    BASE_URL="https://example.com/raw"
    wget() {
      printf "%s\n" "wget:$*"
      printf "#!/usr/bin/env bash\n" > "$2"
    }
    curl() { printf "curl-should-not-run\n" >&2; return 99; }
    chmod() { printf "chmod:$*\n"; }
    download "rm/rm_cert.sh"
    [[ -f "rm_cert.sh" ]]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wget:-qO"* ]]
  [[ "$output" == *"https://example.com/raw/rm/rm_cert.sh"* ]]
  [[ "$output" == *"chmod:+x"* ]]
  [[ "$output" == *"rm_cert.sh"* ]]
  [[ "$output" == *"📥 已保存为 rm_cert.sh"* ]]
}

@test "rm install main_menu exits immediately in noninteractive mode" {
  run bash -c '
    set -euo pipefail
    source "$1"
    JB_NONINTERACTIVE="true"
    set +e
    main_menu
    rc=$?
    set -e
    [ "$rc" -eq 0 ]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VPS GitHub 一键脚本入口"* ]]
  [[ "$output" == *"删除证书"* ]]
}

@test "rm install script catalog includes rm cert entry" {
  run bash -c '
    set -euo pipefail
    source "$1"
    [[ "${SCRIPTS[6]}" == "删除证书:rm/rm_cert.sh" ]]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}

@test "rm install self_elevate_or_die rejects noninteractive without passwordless sudo" {
  run bash -c '
    set +e
    source "$1"
    JB_NONINTERACTIVE="true"
    id() { printf "%s\n" "1000"; }
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "sudo" ]; then
        return 0
      fi
      builtin command "$@"
    }
    sudo() { return 1; }
    log_err() { printf "ERR:%s\n" "$*"; }
    self_elevate_or_die
   ' _ "$LIB_PATH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERR:非交互模式下无法自动提权"* ]]
}

@test "rm install self_elevate_or_die fails when sudo is unavailable" {
  run bash -c '
    set +e
    source "$1"
    id() { printf "%s\n" "1000"; }
    command() {
      if [ "$1" = "-v" ] && [ "$2" = "sudo" ]; then
        return 1
      fi
      builtin command "$@"
    }
    log_err() { printf "ERR:%s\n" "$*"; }
    self_elevate_or_die
   ' _ "$LIB_PATH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERR:未安装 sudo，无法自动提权。"* ]]
}

@test "rm install download fails when wget and curl are missing" {
  run bash -c '
    set +e
    td="$(mktemp -d /tmp/rm.install.missingdl.XXXXXX)"
    trap "rm -rf \"$td\"" EXIT
    cd "$td"
    source "$1"
    command() {
      if [ "$1" = "-v" ] && { [ "$2" = "wget" ] || [ "$2" = "curl" ]; }; then
        return 1
      fi
      builtin command "$@"
    }
    log_err() { printf "ERR:%s\n" "$*"; }
    download "rm/rm_cert.sh"
   ' _ "$LIB_PATH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERR:❌ 系统缺少 wget 或 curl"* ]]
}
