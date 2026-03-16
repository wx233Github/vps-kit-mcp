#!/usr/bin/env bats

setup() {
  REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
  SCRIPT_PATH="${REPO_ROOT}/nginx.sh"
  LIB_PATH="$(mktemp /tmp/nginx.reconfig.domain.XXXXXX.sh)"
  sed '$d' "$SCRIPT_PATH" >"$LIB_PATH"
}

teardown() {
  rm -f "$LIB_PATH"
}

@test "reconfigure domain change reuses config and migrates" {
  run bash -c '
    set -euo pipefail
    source "$1"
    IS_INTERACTIVE_MODE=true

    old_domain="old.example.com"
    new_domain="new.example.com"

    _get_project_json() {
      printf "%s\n" "{\"domain\":\"${old_domain}\",\"resolved_port\":\"8080\",\"cert_file\":\"/etc/ssl/${old_domain}.cer\",\"key_file\":\"/etc/ssl/${old_domain}.key\"}"
    }

    _gather_project_details() {
      printf "%s\n" "{\"domain\":\"${new_domain}\",\"resolved_port\":\"8081\",\"cert_file\":\"/etc/ssl/${new_domain}.cer\",\"key_file\":\"/etc/ssl/${new_domain}.key\"}"
    }

    confirm_or_cancel() {
      case "${1:-}" in
      *证书*) return 1 ;;
      *迁移配置*) return 0 ;;
      *) return 0 ;;
      esac
    }

    snapshot_project_json() { :; }
    _issue_and_install_certificate() { return 0; }

    called_apply=""
    called_delete=""
    called_remove=""
    called_reload="false"

    _apply_project_transaction() { called_apply="$1"; return 0; }
    _delete_project_json() { called_delete="$1"; return 0; }
    _remove_and_disable_nginx_config() { called_remove="$1"; return 0; }
    control_nginx_reload_if_needed() { called_reload="true"; return 0; }

    _handle_reconfigure_project "$old_domain"

    [ "$called_apply" = "$new_domain" ]
    [ "$called_delete" = "$old_domain" ]
    [ "$called_remove" = "$old_domain" ]
    [ "$called_reload" = "true" ]
  ' _ "$LIB_PATH"
  [ "$status" -eq 0 ]
}
