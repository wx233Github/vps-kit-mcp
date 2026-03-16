#!/usr/bin/env bash

_run_cmd() {
  if [ "$DRY_RUN" = "true" ]; then
    log_message INFO "[DRY-RUN] $*"
    return 0
  fi
  "$@"
}

_fix_http2_listen_after_upgrade() {
  local conf_dir="${NGINX_HTTP_CONF_DIR:-/etc/nginx/conf.d}"
  local min_ver="${NGINX_HTTP2_DIRECTIVE_MIN_VERSION:-1.25.1}"

  if [ "$DRY_RUN" != "true" ] && [ -z "${LOCK_OWNER_PID_HTTP:-}" ]; then
    if ! acquire_http_lock; then return 1; fi
  fi

  if ! _ensure_nginx_in_path >/dev/null 2>&1; then
    log_message WARN "未检测到 nginx，跳过 http2 旧写法修正。"
    return 0
  fi

  local nginx_ver
  nginx_ver=$(_get_nginx_version 2>/dev/null || true)
  if [ -z "$nginx_ver" ]; then
    log_message WARN "无法获取 Nginx 版本，跳过 http2 旧写法修正。"
    return 0
  fi

  if ! _version_ge "$nginx_ver" "$min_ver"; then
    log_message INFO "当前 Nginx 版本 ${nginx_ver} 低于 ${min_ver}，跳过 http2 旧写法修正。"
    return 0
  fi

  if [ ! -d "$conf_dir" ]; then
    log_message WARN "未找到 conf.d 目录: ${conf_dir}，跳过 http2 旧写法修正。"
    return 0
  fi

  local -a targets=()
  local f
  shopt -s nullglob
  for f in "$conf_dir"/*.conf; do
    [ -f "$f" ] || continue
    if grep -Eq '^[[:space:]]*listen[[:space:]]+(\[::\]:)?443[[:space:]]+ssl[[:space:]]+http2[[:space:]]*;' "$f"; then
      targets+=("$f")
    fi
  done
  shopt -u nullglob

  if ((${#targets[@]} == 0)); then
    log_message INFO "未发现旧 http2 listen 写法，跳过修正。"
    return 0
  fi

  local -a touched=()
  local tmp
  for f in "${targets[@]}"; do
    if ! _require_safe_path "$f" "修正 http2"; then return 1; fi
    if [ "$DRY_RUN" = "true" ]; then
      log_message INFO "[DRY-RUN] 将备份并修正: ${f}"
      continue
    fi
    local backup="${f}.bak"
    if ! cp -p "$f" "$backup"; then
      log_message ERROR "备份失败: ${f}"
      return 1
    fi
    tmp=$(mktemp "${f}.tmp.XXXXXX")
    chmod 600 "$tmp"
    awk '
      BEGIN {depth=0; in_server=0; server_depth=0; pending=0; has_http2=0}
      {
        line=$0
        probe=$0
        opens=gsub(/\{/, "{", probe)
        closes=gsub(/\}/, "}", probe)
        if (probe ~ /^[ \t]*server[ \t]*\{/) {
          in_server=1
          server_depth=depth+1
          pending=0
          has_http2=0
        }
        if (in_server && line ~ /^[ \t]*http2[ \t]+on[ \t]*;/) {
          has_http2=1
        }
        if (in_server && line ~ /^[ \t]*listen[ \t]+(\[::\]:)?443[ \t]+ssl[ \t]+http2[ \t]*;/) {
          sub(/[ \t]+http2[ \t]*;/, ";", line)
          pending=1
        }
        if (in_server && closes > 0 && (depth - closes) < server_depth) {
          if (pending && has_http2 == 0) {
            print "    http2 on;"
          }
          pending=0
          has_http2=0
          in_server=0
        }
        print line
        depth += opens - closes
      }
    ' "$f" >"$tmp"
    if ! mv "$tmp" "$f"; then
      rm -f "$tmp" || true
      log_message ERROR "写入失败: ${f}"
      return 1
    fi
    chmod --reference="$backup" "$f" 2>/dev/null || true
    touched+=("$f")
  done

  if [ "$DRY_RUN" = "true" ]; then
    log_message INFO "[DRY-RUN] 已完成 http2 旧写法检查。"
    return 0
  fi

  if ((${#touched[@]} == 0)); then
    return 0
  fi

  if ! nginx -t >/dev/null 2>&1; then
    log_message ERROR "http2 修正后 Nginx 配置检测失败，正在回滚..."
    local rollback_ok=1
    local rf
    for rf in "${touched[@]}"; do
      local backup="${rf}.bak"
      if [ -f "$backup" ]; then
        cp -p "$backup" "$rf" || rollback_ok=0
      fi
    done
    nginx -t >/dev/null 2>&1 || true
    [ "$rollback_ok" -eq 1 ] || log_message WARN "回滚过程中存在失败，请手动核查。"
    return 1
  fi

  if ! _run_cmd systemctl reload nginx; then
    log_message WARN "http2 修正后 Nginx 重载失败，请手动执行 systemctl reload nginx。"
  fi
  log_message SUCCESS "已批量修正旧的 http2 listen 写法。"
  return 0
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

  if ! _fix_http2_listen_after_upgrade; then
    log_message WARN "http2 旧写法修正未完成，请手动检查。"
  fi

  log_message SUCCESS "Nginx 官方源升级完成。"
  return 0
}
