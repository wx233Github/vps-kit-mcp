#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.systemd.autostart.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
  STUB_DIR="$(mktemp -d /tmp/nginx.systemd.stub.XXXXXX)"
}

teardown() {
  rm -f "$LIB_PATH"
  rm -rf "$STUB_DIR"
}

@test "systemd nginx auto-start reports conflict with pids" {
  run bash -c '
    set -euo pipefail
    source "$1"
    export PATH="$2:$PATH"
    IS_INTERACTIVE_MODE=true
    LOG_HIDE_CTX_PREFIX=true

    cat >"$2/systemctl" <<"EOF"
#!/usr/bin/env bash
if [ "$1" = "is-active" ]; then exit 1; fi
exit 1
EOF
    cat >"$2/ss" <<"EOF"
#!/usr/bin/env bash
cat <<OUT
LISTEN 0 511 0.0.0.0:80 0.0.0.0:* users:(("nginx",pid=1234,fd=5))
OUT
EOF
    chmod +x "$2/systemctl" "$2/ss"

    _ensure_systemd_nginx_running_or_warn || true
  ' _ "$LIB_PATH" "$STUB_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"❌ systemd nginx 未启动"* ]]
  [[ "$output" == *"pids=nginx:1234"* ]]
}
