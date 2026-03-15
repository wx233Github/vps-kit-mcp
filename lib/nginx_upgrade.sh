#!/usr/bin/env bash

_run_cmd() {
  if [ "$DRY_RUN" = "true" ]; then
    log_message INFO "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

upgrade_nginx_official_repo() {
  _generate_op_id
  if ! check_root; then return 1; fi
  if ! check_dependencies curl gpg; then return 1; fi

  if [ "${IS_INTERACTIVE_MODE}" = "true" ]; then
    if ! confirm_or_cancel "将使用官方源升级 Nginx，期间会短暂中断服务，是否继续?"; then
      return 0
    fi
  fi

  local os_release_file="${NGINX_OS_RELEASE_FILE:-/etc/os-release}"
  if [ ! -f "$os_release_file" ]; then
    log_message ERROR "未找到系统信息文件: ${os_release_file}"
    return "${EX_DATAERR}"
  fi

  # shellcheck disable=SC1090
  . "$os_release_file"

  local distro="debian"
  if [[ "${ID:-}" = "ubuntu" || "${ID_LIKE:-}" == *"ubuntu"* ]]; then
    distro="ubuntu"
  fi

  local codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
    codename=$(lsb_release -cs 2>/dev/null || printf '%s' "")
  fi
  if [ -z "$codename" ]; then
    log_message ERROR "无法识别系统代号，无法配置官方源。"
    return "${EX_DATAERR}"
  fi

  log_message INFO "当前系统: ${distro} ${codename}"

  local backup_root
  backup_root="${BACKUP_DIR:-/root/nginx_ssl_backups}"
  local backup_dir
  backup_dir="${backup_root}/nginx_upgrade_$(date +%Y%m%d_%H%M%S)"
  if ! _run_cmd mkdir -p "$backup_dir"; then return 1; fi
  if ! _run_cmd tar -czf "${backup_dir}/nginx_backup.tgz" /etc/nginx /etc/ssl; then return 1; fi

  local keyring_dir="/etc/apt/keyrings"
  local keyring_file="${keyring_dir}/nginx.gpg"
  local repo_list="/etc/apt/sources.list.d/nginx.list"
  local repo_line="deb [signed-by=${keyring_file}] http://nginx.org/packages/${distro} ${codename} nginx"
  log_message INFO "官方源: ${repo_line}"

  if ! _run_cmd install -m 0755 -d "$keyring_dir"; then return 1; fi

  local key_tmp
  key_tmp=$(mktemp /tmp/nginx.key.XXXXXX) || return 1
  if ! _run_cmd curl -fsSL https://nginx.org/keys/nginx_signing.key -o "$key_tmp"; then
    _run_cmd rm -f "$key_tmp" || true
    return 1
  fi
  if ! _run_cmd gpg --dearmor --yes -o "$keyring_file" "$key_tmp"; then
    _run_cmd rm -f "$key_tmp" || true
    return 1
  fi
  _run_cmd rm -f "$key_tmp" || true
  _run_cmd chmod a+r "$keyring_file" || true

  local repo_tmp
  repo_tmp=$(mktemp /tmp/nginx.repo.XXXXXX) || return 1
  printf '%s\n' "$repo_line" >"$repo_tmp"
  if ! _run_cmd mv "$repo_tmp" "$repo_list"; then
    _run_cmd rm -f "$repo_tmp" || true
    return 1
  fi

  local -a apt_env=(env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=a)
  if ! _run_cmd "${apt_env[@]}" apt-get update -qq; then return 1; fi
  if ! _run_cmd "${apt_env[@]}" apt-get install -y nginx; then return 1; fi

  if ! _run_cmd nginx -t; then
    log_message ERROR "Nginx 配置检测失败，正在回滚..."
    _run_cmd tar -xzf "${backup_dir}/nginx_backup.tgz" -C / || true
    _run_cmd systemctl restart nginx || true
    return 1
  fi
  if ! _run_cmd systemctl restart nginx; then
    log_message ERROR "Nginx 重启失败，正在回滚..."
    _run_cmd tar -xzf "${backup_dir}/nginx_backup.tgz" -C / || true
    _run_cmd systemctl restart nginx || true
    return 1
  fi

  log_message SUCCESS "Nginx 官方源升级完成。"
  return 0
}
