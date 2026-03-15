#!/usr/bin/env bats

@test "build archive url from base_url" {
  tmp_script=$(mktemp /tmp/install.archive.url.XXXXXX.sh)
  cat >"$tmp_script" <<"EOF"
set -euo pipefail
SCRIPT_PATH="/root/aa/vps-kit-mcp/install.sh"
LIB_PATH=$(mktemp /tmp/install.archive.lib.XXXXXX.sh)
sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"

readlink() { printf '%s\n' "/opt/vps_install_modules/install.sh"; }
source() {
  if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
    builtin source "/root/aa/vps-kit-mcp/utils.sh"
    return 0
  fi
  builtin source "$1"
}
source "$LIB_PATH"

BASE_URL="https://raw.githubusercontent.com/wx233Github/vps-kit-mcp/main"
_build_archive_url_from_base
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/wx233Github/vps-kit-mcp/archive/refs/heads/main.tar.gz" ]
}

@test "collect core update list detects changed core files" {
  tmp_script=$(mktemp /tmp/install.update.list.XXXXXX.sh)
  cat >"$tmp_script" <<"EOF"
set -euo pipefail
SCRIPT_PATH="/root/aa/vps-kit-mcp/install.sh"
LIB_PATH=$(mktemp /tmp/install.update.list.lib.XXXXXX.sh)
sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"

readlink() { printf '%s\n' "/opt/vps_install_modules/install.sh"; }
source() {
  if [ "$1" = "/opt/vps_install_modules/utils.sh" ]; then
    builtin source "/root/aa/vps-kit-mcp/utils.sh"
    return 0
  fi
  builtin source "$1"
}
source "$LIB_PATH"

old_dir=$(mktemp -d /tmp/install.update.list.old.XXXXXX)
new_dir=$(mktemp -d /tmp/install.update.list.new.XXXXXX)

INSTALL_DIR="$old_dir"
printf '%s\n' "old" >"${old_dir}/install.sh"
printf '%s\n' "new" >"${new_dir}/install.sh"
printf '%s\n' "same" >"${old_dir}/utils.sh"
printf '%s\n' "same" >"${new_dir}/utils.sh"
printf '%s\n' "cfg" >"${old_dir}/config.json"
printf '%s\n' "cfg" >"${new_dir}/config.json"
printf '%s\n' "ngx" >"${old_dir}/nginx.sh"
printf '%s\n' "ngx" >"${new_dir}/nginx.sh"

_collect_core_update_list "$new_dir"
EOF
  run /bin/bash "$tmp_script"
  rm -f "$tmp_script"
  [ "$status" -eq 0 ]
  [[ "$output" =~ install.sh ]]
}
