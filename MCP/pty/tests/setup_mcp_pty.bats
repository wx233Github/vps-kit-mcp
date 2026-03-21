#!/usr/bin/env bats

setup() {
  export PTY_DIR="${BATS_TEST_DIRNAME%/tests}"
  export TARGET_SCRIPT="${PTY_DIR}/mcp_pty.sh"
}

@test "--help 可正常输出" {
  run bash "$TARGET_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--with-opencode"* ]]
}

@test "未知参数返回 EX_USAGE(64)" {
  run bash "$TARGET_SCRIPT" --not-exists
  [ "$status" -eq 64 ]
  [[ "$output" == *"未知参数"* ]]
}

@test "参数解析支持可选模式与路径覆盖" {
  run bash <<'EOF'
source "$TARGET_SCRIPT"
DRY_RUN="false"
MODE=""
REMOTE_RAW_BASE=""
LOCAL_BASE_DIR=""
OPENCODE_CONFIG_PATH=""
OPENCODE_INSTRUCTIONS_PATH=""
PTY_MCP_SPEC=""
parse_args --with-opencode --dry-run --remote-raw-base "https://example.com/raw" --local-dir "/tmp/mcp-pty" --opencode-config "/tmp/opencode.json" --opencode-instruction-path "/tmp/pty.md" --pty-mcp-spec "pty-mcp==0.2.0"
[ "$MODE" = "opencode" ]
[ "$DRY_RUN" = "true" ]
[ "$REMOTE_RAW_BASE" = "https://example.com/raw" ]
[ "$LOCAL_BASE_DIR" = "/tmp/mcp-pty" ]
[ "$OPENCODE_CONFIG_PATH" = "/tmp/opencode.json" ]
[ "$OPENCODE_INSTRUCTIONS_PATH" = "/tmp/pty.md" ]
[ "$PTY_MCP_SPEC" = "pty-mcp==0.2.0" ]
EOF
  [ "$status" -eq 0 ]
}

@test "PTY_MCP_SPEC 环境变量可作为默认包规格" {
  run env PTY_MCP_SPEC="pty-mcp==9.9.9" bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"
[ "$PTY_MCP_SPEC" = "pty-mcp==9.9.9" ]
EOF
  [ "$status" -eq 0 ]
}

@test "--uninstall 参数可切换到卸载模式" {
  run bash <<'EOF'
source "$TARGET_SCRIPT"
MODE=""
parse_args --uninstall
[ "$MODE" = "uninstall" ]
EOF
  [ "$status" -eq 0 ]
}

@test "opencode 配置写入包含 pty-runner 命令规格与 instructions" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq 不存在，跳过此测试"
  fi

  run bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"
DRY_RUN="false"
PTY_MCP_SPEC="pty-mcp==0.2.0"

tmp_home="$(mktemp -d)"
config_path="${tmp_home}/.config/opencode/opencode.json"
instruction_path="${tmp_home}/.config/opencode/instructions/pty.md"

mkdir -p "$(dirname "$config_path")" "$(dirname "$instruction_path")"
printf "{}\n" >"$config_path"

update_opencode_config "$config_path" "$PTY_MCP_SPEC" "$instruction_path"

jq -e --arg spec "$PTY_MCP_SPEC" --arg ins "$instruction_path" '
  .mcp["pty-runner"].command == ["uvx", "--from", $spec, "pty-mcp"]
  and .mcp["pty-runner"].environment.PATH == "{env:HOME}/.local/bin:{env:HOME}/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  and .mcp["pty-runner"].environment.LANG == "C.UTF-8"
  and .mcp["pty-runner"].environment.LC_ALL == "C.UTF-8"
  and (.instructions | index($ins) != null)
' "$config_path" >/dev/null
EOF
  [ "$status" -eq 0 ]
}

@test "HOME 路径会写入 {env:HOME} 模板" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq 不存在，跳过此测试"
  fi

  run bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"
DRY_RUN="false"
PTY_MCP_SPEC="pty-mcp"

tmp_home="$(mktemp -d)"
config_path="${tmp_home}/.config/opencode/opencode.json"
instruction_path="${HOME}/.config/opencode/instructions/pty.md"

mkdir -p "$(dirname "$config_path")"
cat >"$config_path" <<'JSON'
{
  "instructions": [
    "${HOME}/.config/opencode/instructions/pty.md",
    "{env:HOME}/.config/opencode/instructions/pty.md"
  ]
}
JSON

update_opencode_config "$config_path" "$PTY_MCP_SPEC" "$instruction_path"

jq -e '
  .mcp["pty-runner"].command == ["uvx", "--from", "pty-mcp", "pty-mcp"]
  and (.instructions | index("{env:HOME}/.config/opencode/instructions/pty.md") != null)
  and (.instructions | index("${HOME}/.config/opencode/instructions/pty.md") == null)
' "$config_path" >/dev/null
EOF
  [ "$status" -eq 0 ]
}

@test "CLI 传入的 pty-mcp spec 优先于环境变量" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq 不存在，跳过此测试"
  fi

  run env PTY_MCP_SPEC="pty-mcp==1.0.0" bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"
DRY_RUN="false"
MODE=""
parse_args --pty-mcp-spec "pty-mcp==0.2.0"
[ "$PTY_MCP_SPEC" = "pty-mcp==0.2.0" ]
EOF
  [ "$status" -eq 0 ]
}

@test "resolve_uv_bin 支持 ~/.local/bin/uv" {
  run bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"

tmp_home="$(mktemp -d)"
mkdir -p "${tmp_home}/.local/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"${tmp_home}/.local/bin/uv"
chmod 755 "${tmp_home}/.local/bin/uv"

HOME="$tmp_home"
UV_BIN=""
resolve_uv_bin
[ "$UV_BIN" = "${tmp_home}/.local/bin/uv" ]
EOF
  [ "$status" -eq 0 ]
}

@test "resolve_opencode_bin 支持 ~/.opencode-i18n/bin/opencode" {
  run bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"

tmp_home="$(mktemp -d)"
mkdir -p "${tmp_home}/.opencode-i18n/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"${tmp_home}/.opencode-i18n/bin/opencode"
chmod 755 "${tmp_home}/.opencode-i18n/bin/opencode"

HOME="$tmp_home"
OPENCODE_BIN=""
resolve_opencode_bin
[ "$OPENCODE_BIN" = "${tmp_home}/.opencode-i18n/bin/opencode" ]
EOF
  [ "$status" -eq 0 ]
}

@test "JB_NONINTERACTIVE=true 时跳过交互确认" {
  run bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"

JB_NONINTERACTIVE="true"
confirm_run_if_needed
EOF
  [ "$status" -eq 0 ]
}

@test "卸载清理会删除 opencode 中 pty-runner 与 instructions 关联" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq 不存在，跳过此测试"
  fi

  run bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"
DRY_RUN="false"

tmp_home="$(mktemp -d)"
config_path="${tmp_home}/.config/opencode/opencode.json"
instruction_path="${tmp_home}/.config/opencode/instructions/pty.md"

mkdir -p "$(dirname "$config_path")" "$(dirname "$instruction_path")"
printf "x" >"$instruction_path"

cat >"$config_path" <<JSON
{
  "mcp": {
    "pty-runner": {
      "type": "local"
    }
  },
  "instructions": [
    "${instruction_path}",
    "{env:HOME}/.config/opencode/instructions/pty.md",
    "other.md"
  ]
}
JSON

cleanup_opencode_config "$config_path" "$instruction_path"

jq -e --arg ins "$instruction_path" '
  (.mcp | has("pty-runner") | not)
  and (.instructions | index($ins) == null)
' "$config_path" >/dev/null
EOF
  [ "$status" -eq 0 ]
}
