#!/usr/bin/env bats

@test "upgrade nginx official repo runs in dry-run mode" {
  tmp_script=$(mktemp /tmp/nginx.upgrade.dryrun.XXXXXX.sh)
  cat >"$tmp_script" <<"EOF"
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin"

SCRIPT_PATH="/root/aa/vps-kit-mcp/nginx.sh"
LIB_PATH=$(mktemp /tmp/nginx.upgrade.lib.XXXXXX.sh)
sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"

realpath() { printf '%s\n' "/root/aa/vps-kit-mcp/nginx.sh"; }

source "$LIB_PATH"

log_message() { printf '%s\n' "$2"; }
check_root() { return 0; }
check_dependencies() { return 0; }

os_release=$(mktemp /tmp/nginx.os-release.XXXXXX)
cat >"$os_release" <<"OSREL"
ID=ubuntu
VERSION_CODENAME=jammy
OSREL

NGINX_OS_RELEASE_FILE="$os_release"
IS_INTERACTIVE_MODE=false
DRY_RUN=true

upgrade_nginx_official_repo
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
  [ "$status" -eq 0 ]
  [[ "$output" =~ 当前系统:\ ubuntu\ jammy ]]
  [[ "$output" =~ 官方源:\ deb\ \[signed-by=/etc/apt/keyrings/nginx.gpg\]\ http://nginx.org/packages/ubuntu\ jammy\ nginx ]]
  [[ "$output" =~ 升级日志:\ /var/log/nginx_upgrade.log ]]
  [[ "$output" =~ Nginx\ 官方源升级完成 ]]
}
