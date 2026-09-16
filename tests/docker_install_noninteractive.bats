#!/usr/bin/env bats

# 覆盖: 首次安装 Docker 时“卡住不动、Ctrl+C 后却发现已安装”的问题。
# 根因是 execute_with_spinner 把步骤输出重定向到日志并在后台执行，
# 一旦 apt/dpkg/debconf 询问交互输入，提示被吞进日志而无人应答。

setup() {
	REPO_ROOT="${BATS_TEST_DIRNAME%/tests}"
	DOCKER_LIB="$(mktemp /tmp/docker.install.noninteractive.XXXXXX.sh)"
	awk '/^UTILS_PATH=/ {print "UTILS_PATH=\"/tmp/__missing_utils__\""; next} {print}' "${REPO_ROOT}/docker.sh" | sed '$d' >"$DOCKER_LIB"
}

teardown() {
	rm -f "$DOCKER_LIB"
}

@test "execute_with_spinner 以关闭 stdin 的方式运行步骤，交互式步骤立即报错而非挂起" {
	run bash -c '
    set -euo pipefail
    source "$1"
    execute_with_spinner "交互步骤测试" bash -c "read -r answer || exit 3; echo \"got:\$answer\""
  ' _ "$DOCKER_LIB"
	[ "$status" -eq 1 ]
	[[ "$output" == *"✗ 失败"* ]]
	[[ "$output" == *"操作失败，脚本已终止"* ]]
}

@test "execute_with_spinner 对超时步骤给出超时诊断并终止" {
	run bash -c '
    set -euo pipefail
    source "$1"
    DOCKER_SPINNER_TIMEOUT=1
    execute_with_spinner "超时步骤测试" sleep 30
  ' _ "$DOCKER_LIB"
	[ "$status" -eq 1 ]
	[[ "$output" == *"步骤超时"* ]]
}

@test "apt_get_install_noninteractive 注入非交互环境与 dpkg 覆盖选项" {
	run bash -c '
    set -euo pipefail
    source "$1"
    run_with_sudo() { printf "SUDO:"; printf "%s " "$@"; printf "\n"; }
    apt_get_install_noninteractive docker-ce containerd.io
  ' _ "$DOCKER_LIB"
	[ "$status" -eq 0 ]
	[[ "$output" == *"DEBIAN_FRONTEND=noninteractive"* ]]
	[[ "$output" == *"NEEDRESTART_MODE=a"* ]]
	[[ "$output" == *"apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold docker-ce containerd.io"* ]]
}

@test "install_docker 的安装步骤为非交互且不再用 hello-world 阻塞流程" {
	run bash -c '
    set -euo pipefail
    source "$1"
    logfile="$(mktemp /tmp/docker.install.flow.XXXXXX.log)"
    confirm_action() { return 0; }
    determine_install_source() { DOCKER_INSTALL_URL="$DOCKER_URL_OFFICIAL"; }
    check_distro() { DISTRO=ubuntu; CODENAME=noble; DOCKER_REPO_CODENAME=noble; }
    resolve_docker_repo_codename() { :; }
    cleanup_docker_apt_source() { :; }
    remove_legacy_docker_packages() { :; }
    ensure_docker_repo_ready() { :; }
    install_docker_gpg_key() { :; }
    verify_docker_packages_available() { :; }
    get_docker_status() { DOCKER_VERSION="Docker version 27.0.0"; COMPOSE_VERSION="v2.28.0"; }
    configure_docker_mirror() { :; }
    add_user_to_docker_group() { :; }
    dpkg_configure_pending() { printf "DPKG_CONFIGURE\n" >>"$logfile"; }
    systemctl() { return 1; }
    run_with_sudo() {
      if [ "$1" = "docker" ] && [ "$2" = "run" ]; then
        printf "HELLO_WORLD\n" >>"$logfile"
      fi
      printf "SUDO:" >>"$logfile"; printf "%s " "$@" >>"$logfile"; printf "\n" >>"$logfile"
      return 0
    }
    install_docker >/dev/null 2>&1
    cat "$logfile"
    rm -f "$logfile"
  ' _ "$DOCKER_LIB"
	[ "$status" -eq 0 ]
	# 安装前修复上一次被中断的 dpkg 状态
	[[ "$output" == *"DPKG_CONFIGURE"* ]]
	# 安装命令本身必须是非交互的
	[[ "$output" == *"DEBIAN_FRONTEND=noninteractive"* ]]
	[[ "$output" == *"apt-get install -y"* ]]
	[[ "$output" == *"docker-ce"* ]]
	# 服务未运行时不得执行 hello-world 功能测试
	[[ "$output" != *"HELLO_WORLD"* ]]
}

@test "verify_docker_packages_available 在源缺少候选版本时报错" {
	run bash -c '
    set -euo pipefail
    source "$1"
    run_with_sudo() {
      if [ "$1" = "env" ]; then
        printf "docker-ce:\n  Installed: (none)\n  Candidate: 5:27.0.0-1\ncontainerd.io:\n  Installed: (none)\n  Candidate: (none)\n"
        return 0
      fi
      return 0
    }
    if verify_docker_packages_available; then
      echo "UNEXPECTED_SUCCESS"
      exit 1
    fi
    echo "EXPECTED_FAILURE"
  ' _ "$DOCKER_LIB"
	[ "$status" -eq 0 ]
	[[ "$output" == *"EXPECTED_FAILURE"* ]]
	[[ "$output" != *"UNEXPECTED_SUCCESS"* ]]
}

@test "install_docker 恢复被中断的上次安装：先修 dpkg 再装，失败也不再静默" {
	run bash -c '
    set -euo pipefail
    source "$1"
    logfile="$(mktemp /tmp/docker.install.resume.XXXXXX.log)"
    confirm_action() { return 0; }
    determine_install_source() { DOCKER_INSTALL_URL="$DOCKER_URL_OFFICIAL"; }
    check_distro() { DISTRO=ubuntu; CODENAME=noble; DOCKER_REPO_CODENAME=noble; }
    resolve_docker_repo_codename() { :; }
    cleanup_docker_apt_source() { :; }
    remove_legacy_docker_packages() { :; }
    ensure_docker_repo_ready() { :; }
    install_docker_gpg_key() { :; }
    verify_docker_packages_available() { :; }
    get_docker_status() { :; }
    configure_docker_mirror() { :; }
    add_user_to_docker_group() { :; }
    systemctl() { return 0; }
    # 模拟“上次安装被 Ctrl+C 打断”，dpkg 处于未配置状态
    dpkg_configure_pending() { printf "DPKG_REPAIR\n" >>"$logfile"; }
    apt_get_install_noninteractive() {
      printf "INSTALL:%s\n" "$*" >>"$logfile"
      grep -q "DPKG_REPAIR" "$logfile" || { printf "ORDER_VIOLATION\n" >>"$logfile"; return 1; }
      return 0
    }
    run_with_sudo() { return 0; }
    install_docker >/dev/null 2>&1
    cat "$logfile"
    rm -f "$logfile"
  ' _ "$DOCKER_LIB"
	[ "$status" -eq 0 ]
	[[ "$output" == *"DPKG_REPAIR"* ]]
	[[ "$output" == *"INSTALL:docker-ce"* ]]
	[[ "$output" != *"ORDER_VIOLATION"* ]]
}
