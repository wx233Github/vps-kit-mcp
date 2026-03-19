#!/usr/bin/env bats

setup() {
  export PTY_DIR="${BATS_TEST_DIRNAME%/tests}"
  export TARGET_SCRIPT="${PTY_DIR}/mcp_pty.sh"
  export RUNNER_PATH="${PTY_DIR}/pty-runner.py"
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
parse_args --with-opencode --dry-run --remote-raw-base "https://example.com/raw" --local-dir "/tmp/mcp-pty" --opencode-config "/tmp/opencode.json" --opencode-instruction-path "/tmp/pty.md"
[ "$MODE" = "opencode" ]
[ "$DRY_RUN" = "true" ]
[ "$REMOTE_RAW_BASE" = "https://example.com/raw" ]
[ "$LOCAL_BASE_DIR" = "/tmp/mcp-pty" ]
[ "$OPENCODE_CONFIG_PATH" = "/tmp/opencode.json" ]
[ "$OPENCODE_INSTRUCTIONS_PATH" = "/tmp/pty.md" ]
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

@test "opencode 配置写入包含 pty-runner 与 instructions" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq 不存在，跳过此测试"
  fi

  run bash <<'EOF'
set -euo pipefail
source "$TARGET_SCRIPT"
DRY_RUN="false"

tmp_home="$(mktemp -d)"
config_path="${tmp_home}/.config/opencode/opencode.json"
server_path="${tmp_home}/mcp/mcp-pty/server.py"
instruction_path="${tmp_home}/.config/opencode/instructions/pty.md"

mkdir -p "$(dirname "$config_path")" "$(dirname "$server_path")" "$(dirname "$instruction_path")"
printf "{}\n" >"$config_path"

update_opencode_config "$config_path" "$server_path" "$instruction_path"

jq -e --arg server "$server_path" --arg ins "$instruction_path" '
  .mcp["pty-runner"].command == ["uv", "run", "--script", $server]
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

tmp_home="$(mktemp -d)"
config_path="${tmp_home}/.config/opencode/opencode.json"
server_path="${HOME}/mcp/mcp-pty/server.py"
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

update_opencode_config "$config_path" "$server_path" "$instruction_path"

jq -e '
  .mcp["pty-runner"].command == ["uv", "run", "--script", "{env:HOME}/mcp/mcp-pty/server.py"]
  and (.instructions | index("{env:HOME}/.config/opencode/instructions/pty.md") != null)
  and (.instructions | index("${HOME}/.config/opencode/instructions/pty.md") == null)
' "$config_path" >/dev/null
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

@test "默认策略下 pty-runner 暴露核心工具并隐藏 admin/control 工具" {
  run python3 - <<'PY'
import json
import os
import pathlib
import subprocess

runner = pathlib.Path(os.environ['RUNNER_PATH'])
p = subprocess.Popen(
    ['python3', str(runner)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def call(msg_id, method, params=None):
    payload = {'jsonrpc': '2.0', 'id': msg_id, 'method': method}
    if params is not None:
        payload['params'] = params
    p.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        raise RuntimeError('pty-runner 未返回响应')
    return json.loads(line)

try:
    init = call(1, 'initialize', {'protocolVersion': '2024-11-05'})
    assert init['result']['serverInfo']['name'] == 'pty-mcp'

    tools = call(2, 'tools/list', {})
    names = {tool['name'] for tool in tools['result']['tools']}
    expected = {
        'pty_spawn',
        'pty_read',
        'pty_read_until',
        'pty_read_until_any',
        'pty_read_quiescent',
        'pty_read_stdout',
        'pty_read_stderr',
        'pty_read_at',
        'pty_prompt',
        'confirm_dangerous_command',
        'pty_write',
        'pty_resize',
        'pty_close',
        'pty_status',
        'pty_wait',
        'pty_list',
    }
    missing = sorted(expected - names)
    assert not missing, f'缺少工具: {missing}'
    hidden = {
        'pty_signal',
        'pty_close_all',
        'set_default_cwd',
        'get_default_cwd',
        'set_limits',
        'get_limits',
        'pty_metrics',
        'pty_health',
    }
    leaked = sorted(hidden & names)
    assert not leaked, f'默认策略不应暴露: {leaked}'
finally:
    try:
        p.terminate()
    except Exception:
        pass
    try:
        p.wait(timeout=2)
    except Exception:
        pass
PY
  [ "$status" -eq 0 ]
}

@test "启用 admin/control 策略后暴露管理工具" {
  run env PTY_MCP_ENABLE_ADMIN_TOOLS=1 PTY_MCP_ENABLE_CONTROL_TOOLS=1 python3 - <<'PY'
import json
import os
import pathlib
import subprocess

runner = pathlib.Path(os.environ['RUNNER_PATH'])
p = subprocess.Popen(
    ['python3', str(runner)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def call(msg_id, method, params=None):
    payload = {'jsonrpc': '2.0', 'id': msg_id, 'method': method}
    if params is not None:
        payload['params'] = params
    p.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        raise RuntimeError('pty-runner 未返回响应')
    return json.loads(line)

try:
    call(1, 'initialize', {'protocolVersion': '2024-11-05'})
    tools = call(2, 'tools/list', {})
    names = {tool['name'] for tool in tools['result']['tools']}
    expected = {
        'pty_signal',
        'pty_close_all',
        'set_default_cwd',
        'get_default_cwd',
        'set_limits',
        'get_limits',
        'pty_metrics',
        'pty_health',
    }
    missing = sorted(expected - names)
    assert not missing, f'启用策略后缺少工具: {missing}'
finally:
    try:
        p.terminate()
    except Exception:
        pass
    try:
        p.wait(timeout=2)
    except Exception:
        pass
PY
  [ "$status" -eq 0 ]
}

@test "危险命令 token、owner 与 scope 策略生效" {
  run python3 - <<'PY'
import json
import os
import pathlib
import subprocess
import time

runner = pathlib.Path(os.environ['RUNNER_PATH'])
env = {
    'PTY_MCP_DANGEROUS_PATTERNS': r'printf dangerous-ok',
    'PTY_MCP_ENABLE_CONTROL_TOOLS': '1',
}

p = subprocess.Popen(
    ['python3', str(runner)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env={**__import__('os').environ, **env},
)

def call(msg_id, method, params=None):
    payload = {'jsonrpc': '2.0', 'id': msg_id, 'method': method}
    if params is not None:
        payload['params'] = params
    p.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        raise RuntimeError('pty-runner 未返回响应')
    return json.loads(line)

def tool(msg_id, name, arguments=None):
    return call(msg_id, 'tools/call', {'name': name, 'arguments': arguments or {}})

try:
    call(1, 'initialize', {'protocolVersion': '2024-11-05'})

    denied = tool(2, 'pty_spawn', {
        'command': 'printf dangerous-ok',
        'owner': 'alice',
        'scope': 'read-write',
    })
    assert 'error' in denied and 'confirmation token required' in denied['error']['message']

    confirm = tool(3, 'confirm_dangerous_command', {
        'command': 'printf dangerous-ok',
        'justification': 'test dangerous token flow',
        'owner': 'alice',
        'scope': 'read-write',
    })
    payload = json.loads(confirm['result']['content'][0]['text'])
    token = payload['confirm_token']
    assert token
    assert payload['expires_at'] > time.time()

    spawn = tool(4, 'pty_spawn', {
        'command': 'printf dangerous-ok',
        'owner': 'alice',
        'scope': 'read-write',
        'dangerous_confirm_token': token,
    })
    sid = spawn['result']['content'][0]['text']

    read_ok = tool(5, 'pty_read', {
        'session_id': sid,
        'owner': 'alice',
        'timeout_ms': 1000,
    })
    assert 'dangerous-ok' in read_ok['result']['content'][0]['text']

    read_bad = tool(6, 'pty_read', {
        'session_id': sid,
        'owner': 'bob',
        'timeout_ms': 1000,
    })
    assert 'error' in read_bad and 'owner mismatch' in read_bad['error']['message']

    list_denied = tool(7, 'pty_list', {})
    assert 'error' in list_denied and 'owner is required' in list_denied['error']['message']

    cat_spawn = tool(8, 'pty_spawn', {
        'command': 'cat',
        'owner': 'alice',
        'scope': 'read-only',
    })
    cat_sid = cat_spawn['result']['content'][0]['text']

    write_denied = tool(9, 'pty_write', {
        'session_id': cat_sid,
        'owner': 'alice',
        'data': 'hello\n',
    })
    assert 'error' in write_denied and 'does not allow' in write_denied['error']['message']

    control_spawn = tool(10, 'pty_spawn', {
        'command': 'sleep 5',
        'owner': 'alice',
        'scope': 'control',
    })
    control_sid = control_spawn['result']['content'][0]['text']

    signal_ok = tool(11, 'pty_signal', {
        'session_id': control_sid,
        'owner': 'alice',
        'sig': 'SIGTERM',
    })
    assert 'result' in signal_ok

    second_use = tool(12, 'pty_spawn', {
        'command': 'printf dangerous-ok',
        'owner': 'alice',
        'scope': 'read-write',
        'dangerous_confirm_token': token,
    })
    assert 'error' in second_use and ('invalid or expired' in second_use['error']['message'] or 'already used' in second_use['error']['message'])
finally:
    try:
        p.terminate()
    except Exception:
        pass
    try:
        p.wait(timeout=2)
    except Exception:
        pass
PY
  [ "$status" -eq 0 ]
}

@test "危险命令 token 过期与绑定不匹配会被拒绝" {
  run python3 - <<'PY'
import json
import os
import pathlib
import subprocess
import time

runner = pathlib.Path(os.environ['RUNNER_PATH'])
env = {
    'PTY_MCP_DANGEROUS_PATTERNS': r'printf dangerous-expire;printf dangerous-alt',
    'PTY_MCP_DANGEROUS_CONFIRM_TTL_SEC': '1',
}

p = subprocess.Popen(
    ['python3', str(runner)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env={**os.environ, **env},
)

def call(msg_id, method, params=None):
    payload = {'jsonrpc': '2.0', 'id': msg_id, 'method': method}
    if params is not None:
        payload['params'] = params
    p.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        raise RuntimeError('pty-runner 未返回响应')
    return json.loads(line)

def tool(msg_id, name, arguments=None):
    return call(msg_id, 'tools/call', {'name': name, 'arguments': arguments or {}})

try:
    call(1, 'initialize', {'protocolVersion': '2024-11-05'})

    mismatch_confirm = tool(2, 'confirm_dangerous_command', {
        'command': 'printf dangerous-expire',
        'justification': 'mismatch test',
        'owner': 'alice',
        'scope': 'read-write',
    })
    mismatch_token = json.loads(mismatch_confirm['result']['content'][0]['text'])['confirm_token']

    mismatch = tool(3, 'pty_spawn', {
        'command': 'printf dangerous-alt',
        'owner': 'alice',
        'scope': 'read-write',
        'dangerous_confirm_token': mismatch_token,
    })
    assert 'error' in mismatch and 'does not match command' in mismatch['error']['message']

    expire_confirm = tool(4, 'confirm_dangerous_command', {
        'command': 'printf dangerous-expire',
        'justification': 'ttl test',
        'owner': 'alice',
        'scope': 'read-write',
    })
    expire_token = json.loads(expire_confirm['result']['content'][0]['text'])['confirm_token']
    time.sleep(1.5)

    expired = tool(5, 'pty_spawn', {
        'command': 'printf dangerous-expire',
        'owner': 'alice',
        'scope': 'read-write',
        'dangerous_confirm_token': expire_token,
    })
    assert 'error' in expired and ('invalid or expired' in expired['error']['message'] or 'expired' in expired['error']['message'])
finally:
    try:
        p.terminate()
    except Exception:
        pass
    try:
        p.wait(timeout=2)
    except Exception:
        pass
PY
  [ "$status" -eq 0 ]
}

@test "显式开启兼容模式后可恢复旧的危险命令确认路径" {
  run env PTY_MCP_DANGEROUS_LEGACY_MODE=1 PTY_MCP_REQUIRE_OWNER=0 python3 - <<'PY'
import json
import os
import pathlib
import subprocess

runner = pathlib.Path(os.environ['RUNNER_PATH'])
env = {
    'PTY_MCP_DANGEROUS_PATTERNS': r'printf dangerous-legacy',
}

p = subprocess.Popen(
    ['python3', str(runner)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env={**os.environ, **env},
)

def call(msg_id, method, params=None):
    payload = {'jsonrpc': '2.0', 'id': msg_id, 'method': method}
    if params is not None:
        payload['params'] = params
    p.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        raise RuntimeError('pty-runner 未返回响应')
    return json.loads(line)

def tool(msg_id, name, arguments=None):
    return call(msg_id, 'tools/call', {'name': name, 'arguments': arguments or {}})

try:
    call(1, 'initialize', {'protocolVersion': '2024-11-05'})
    spawn = tool(2, 'pty_spawn', {
        'command': 'printf dangerous-legacy',
        'dangerous_justification': 'legacy compatibility test',
    })
    assert 'result' in spawn
finally:
    try:
        p.terminate()
    except Exception:
        pass
    try:
        p.wait(timeout=2)
    except Exception:
        pass
PY
  [ "$status" -eq 0 ]
}

@test "dangerous_confirm_token 在 owner 不匹配时会被拒绝" {
  run python3 - <<'PY'
import json
import os
import pathlib
import subprocess

runner = pathlib.Path(os.environ['RUNNER_PATH'])
env = {
    'PTY_MCP_DANGEROUS_PATTERNS': r'printf dangerous-owner',
}

p = subprocess.Popen(
    ['python3', str(runner)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env={**os.environ, **env},
)

def call(msg_id, method, params=None):
    payload = {'jsonrpc': '2.0', 'id': msg_id, 'method': method}
    if params is not None:
        payload['params'] = params
    p.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        raise RuntimeError('pty-runner 未返回响应')
    return json.loads(line)

def tool(msg_id, name, arguments=None):
    return call(msg_id, 'tools/call', {'name': name, 'arguments': arguments or {}})

try:
    call(1, 'initialize', {'protocolVersion': '2024-11-05'})
    confirm = tool(2, 'confirm_dangerous_command', {
        'command': 'printf dangerous-owner',
        'justification': 'owner mismatch test',
        'owner': 'alice',
        'scope': 'read-write',
    })
    token = json.loads(confirm['result']['content'][0]['text'])['confirm_token']

    denied = tool(3, 'pty_spawn', {
        'command': 'printf dangerous-owner',
        'owner': 'bob',
        'scope': 'read-write',
        'dangerous_confirm_token': token,
    })
    assert 'error' in denied and 'owner mismatch' in denied['error']['message']
finally:
    try:
        p.terminate()
    except Exception:
        pass
    try:
        p.wait(timeout=2)
    except Exception:
        pass
PY
  [ "$status" -eq 0 ]
}

@test "dangerous_confirm_token 在 scope 不匹配时会被拒绝" {
  run python3 - <<'PY'
import json
import os
import pathlib
import subprocess

runner = pathlib.Path(os.environ['RUNNER_PATH'])
env = {
    'PTY_MCP_DANGEROUS_PATTERNS': r'printf dangerous-scope',
}

p = subprocess.Popen(
    ['python3', str(runner)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env={**os.environ, **env},
)

def call(msg_id, method, params=None):
    payload = {'jsonrpc': '2.0', 'id': msg_id, 'method': method}
    if params is not None:
        payload['params'] = params
    p.stdin.write(json.dumps(payload, ensure_ascii=False) + '\n')
    p.stdin.flush()
    line = p.stdout.readline().strip()
    if not line:
        raise RuntimeError('pty-runner 未返回响应')
    return json.loads(line)

def tool(msg_id, name, arguments=None):
    return call(msg_id, 'tools/call', {'name': name, 'arguments': arguments or {}})

try:
    call(1, 'initialize', {'protocolVersion': '2024-11-05'})
    confirm = tool(2, 'confirm_dangerous_command', {
        'command': 'printf dangerous-scope',
        'justification': 'scope mismatch test',
        'owner': 'alice',
        'scope': 'read-write',
    })
    token = json.loads(confirm['result']['content'][0]['text'])['confirm_token']

    denied = tool(3, 'pty_spawn', {
        'command': 'printf dangerous-scope',
        'owner': 'alice',
        'scope': 'control',
        'dangerous_confirm_token': token,
    })
    assert 'error' in denied and 'scope mismatch' in denied['error']['message']
finally:
    try:
        p.terminate()
    except Exception:
        pass
    try:
        p.wait(timeout=2)
    except Exception:
        pass
PY
  [ "$status" -eq 0 ]
}
