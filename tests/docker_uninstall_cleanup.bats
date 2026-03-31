#!/usr/bin/env bats

@test "uninstall_docker 在缺少 groupdel 时仅告警不中断" {
	run bash <<'EOF'
set -euo pipefail

script_copy=$(mktemp /tmp/docker.uninstall.cleanup.XXXXXX.sh)
sed '$d' /root/aa/vps-kit-mcp/docker.sh >"$script_copy"
python3 - <<'PY' "$script_copy"
from pathlib import Path
path = Path(__import__('sys').argv[1])
text = path.read_text()
text = text.replace('/opt/vps_install_modules/utils.sh', '/tmp/__missing_utils__.sh')
path.write_text(text)
PY
source "$script_copy"
rm -f "$script_copy"

docker_group_members="root"
confirm_action() { return 0; }
log_info() { :; }
log_success() { :; }
log_warn() { printf 'WARN:%s\n' "$*"; }
log_err() { printf 'ERR:%s\n' "$*" >&2; }
ensure_safe_path() { return 0; }
run_destructive_with_sudo() {
  if [ "$1" = "gpasswd" ]; then
    docker_group_members=""
    return 0
  fi
  if [ "$1" = "groupdel" ]; then
    return 127
  fi
  return 0
}
run_with_sudo() {
  return 0
}
execute_with_spinner() {
  local _message="$1"
  shift
  "$@"
}
getent() {
  if [ "$1" = "group" ] && [ "$2" = "docker" ]; then
    printf 'docker:x:999:%s\n' "$docker_group_members"
    return 0
  fi
  return 2
}

uninstall_docker
EOF
	[ "$status" -eq 0 ]
	[[ "$output" == *"WARN:"* ]]
	[[ "$output" == *"docker' 组删除失败"* || "$output" == *"缺少 groupdel"* ]]
}
