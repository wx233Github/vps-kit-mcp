# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///

#!/usr/bin/env python3
import os, sys, json, time, select, subprocess, fcntl, struct, termios, traceback, signal, threading, re, shlex
import tty
from importlib.metadata import PackageNotFoundError, version as pkg_version
import pty


# ---------------- Tuning (non-security) ----------------
def _env_int(name: str, default: int) -> int:
    """读取整型环境变量，失败则回退默认值。"""
    val = os.environ.get(name)
    if val is None:
        return default
    try:
        return int(val)
    except Exception:
        return default


MAX_SESSIONS = _env_int("PTY_MCP_MAX_SESSIONS", 20)
IDLE_TIMEOUT_SEC = _env_int("PTY_MCP_IDLE_TIMEOUT_SEC", 15 * 60)
IDLE_GRACE_SEC = _env_int("PTY_MCP_IDLE_GRACE_SEC", 0)
GC_INTERVAL_SEC = _env_int("PTY_MCP_GC_INTERVAL_SEC", 5)
RING_MAX_BYTES = _env_int("PTY_MCP_RING_MAX_BYTES", 1 * 1024 * 1024)
DEFAULT_READ_TIMEOUT_MS = _env_int("PTY_MCP_READ_TIMEOUT_MS", 300)
DEFAULT_MAX_CHARS = _env_int("PTY_MCP_MAX_CHARS", 8000)
READ_CHUNK_BYTES = _env_int("PTY_MCP_READ_CHUNK_BYTES", 4096)
READ_UNTIL_MAX_MS = _env_int("PTY_MCP_READ_UNTIL_MAX_MS", 60000)
SPAWN_TIMEOUT_SEC = _env_int("PTY_MCP_SPAWN_TIMEOUT_SEC", 0)
OUTPUT_RATE_BPS = _env_int("PTY_MCP_OUTPUT_RATE_BPS", 0)
INPUT_RATE_BPS = _env_int("PTY_MCP_INPUT_RATE_BPS", 0)
QUIESCENCE_MS = _env_int("PTY_MCP_QUIESCENCE_MS", 300)
SESSION_LOG_DIR = os.environ.get("PTY_MCP_SESSION_LOG_DIR")
DEFAULT_BACKEND = os.environ.get("PTY_MCP_BACKEND", "subprocess")
DEFAULT_CWD = None
DANGEROUS_CONFIRM_TTL_SEC = _env_int("PTY_MCP_DANGEROUS_CONFIRM_TTL_SEC", 300)
REQUIRE_OWNER = os.environ.get("PTY_MCP_REQUIRE_OWNER", "1") in (
    "1",
    "true",
    "yes",
)
ENABLE_ADMIN_TOOLS = os.environ.get("PTY_MCP_ENABLE_ADMIN_TOOLS", "0") in (
    "1",
    "true",
    "yes",
)
ENABLE_CONTROL_TOOLS = os.environ.get("PTY_MCP_ENABLE_CONTROL_TOOLS", "0") in (
    "1",
    "true",
    "yes",
)
DANGEROUS_LEGACY_MODE = os.environ.get("PTY_MCP_DANGEROUS_LEGACY_MODE", "0") in (
    "1",
    "true",
    "yes",
)

FRAMING = None  # "lsp" (Content-Length) or "line" (NDJSON)

_last_gc = 0.0
_log_rate = {}  # key -> last_ts
_LOG_LEVEL = os.environ.get("PTY_MCP_LOG", "info").lower()
_LOG_FORMAT = os.environ.get("PTY_MCP_LOG_FORMAT", "plain").lower()
# 是否在 pty_spawn 返回元数据
_SPAWN_META = os.environ.get("PTY_MCP_SPAWN_META", "0") in ("1", "true", "yes")
_LOG_LEVELS = {"debug": 10, "info": 20, "warn": 30, "error": 40}
_server_started = time.time()


def _should_log(level: str) -> bool:
    return _LOG_LEVELS.get(level, 20) >= _LOG_LEVELS.get(_LOG_LEVEL, 20)


def _log(*a, level: str = "info"):
    if not _should_log(level):
        return
    if _LOG_FORMAT == "json":
        # 结构化日志便于检索与聚合
        msg = " ".join(str(x) for x in a)
        payload = {
            "ts": time.time(),
            "level": level,
            "pid": os.getpid(),
            "msg": msg,
        }
        sys.stderr.write(json.dumps(payload, ensure_ascii=False) + "\n")
        sys.stderr.flush()
    else:
        print(*a, file=sys.stderr, flush=True)


def _log_limited(key: str, *a, interval_sec: float = 5.0):
    now = time.time()
    last = _log_rate.get(key, 0.0)
    if now - last >= interval_sec:
        _log_rate[key] = now
        _log(*a, level="warn")


def _dangerous_patterns():
    raw = os.environ.get("PTY_MCP_DANGEROUS_PATTERNS")
    if raw:
        return [p for p in raw.split(";") if p]
    return [
        r"\brm\s+-rf\s+/$",
        r"\brm\s+-rf\s+/\b",
        r"\bmkfs\b",
        r"\bdd\s+if=/dev/zero\b",
        r"\bshutdown\b",
        r"\breboot\b",
        r"\bpoweroff\b",
    ]


def _is_dangerous_command(command: str):
    cmd = _strish(command, "")
    matches = []
    for pat in _dangerous_patterns():
        try:
            if re.search(pat, cmd):
                matches.append(pat)
        except Exception:
            continue
    return matches


def _new_confirm_token():
    return f"dc_{os.urandom(16).hex()}"


def _normalize_command_for_confirmation(command: str) -> str:
    return _strish(command, "").strip()


def _gc_dangerous_confirmations():
    now = _now()
    expired = []
    for token, item in dangerous_confirmations.items():
        if item.get("used"):
            expired.append(token)
            continue
        if item.get("expires_at", 0) <= now:
            expired.append(token)
    for token in expired:
        dangerous_confirmations.pop(token, None)


def _issue_dangerous_confirmation(
    command: str, justification: str, owner=None, scope=None
):
    _gc_dangerous_confirmations()
    token = _new_confirm_token()
    now = _now()
    normalized = _normalize_command_for_confirmation(command)
    matches = _is_dangerous_command(normalized)
    item = {
        "token": token,
        "command": normalized,
        "owner": _strish(owner, "").strip(),
        "scope": _strish(scope, "").strip(),
        "created_at": now,
        "expires_at": now + DANGEROUS_CONFIRM_TTL_SEC,
        "used": False,
        "justification": _strish(justification, "").strip(),
        "matches": matches,
    }
    dangerous_confirmations[token] = item
    return item


def _consume_dangerous_confirmation(token: str, command: str, owner=None, scope=None):
    _gc_dangerous_confirmations()
    token = _strish(token, "").strip()
    item = dangerous_confirmations.get(token)
    if not item:
        raise RuntimeError("invalid or expired dangerous confirmation token")
    if item.get("used"):
        raise RuntimeError("dangerous confirmation token already used")

    normalized = _normalize_command_for_confirmation(command)
    if item.get("command") != normalized:
        raise RuntimeError("dangerous confirmation token does not match command")

    expected_owner = _strish(item.get("owner"), "").strip()
    actual_owner = _strish(owner, "").strip()
    if expected_owner and expected_owner != actual_owner:
        raise RuntimeError("dangerous confirmation token owner mismatch")

    expected_scope = _strish(item.get("scope"), "").strip()
    actual_scope = _strish(scope, "").strip()
    if expected_scope and expected_scope != actual_scope:
        raise RuntimeError("dangerous confirmation token scope mismatch")

    item["used"] = True
    dangerous_confirmations.pop(token, None)
    return item


def _tool_access_level(name: str) -> str:
    if name in (
        "pty_close_all",
        "set_limits",
        "set_default_cwd",
        "get_limits",
        "get_default_cwd",
        "pty_metrics",
        "pty_health",
    ):
        return "admin"
    if name in ("pty_signal",):
        return "control"
    if name in ("pty_write", "pty_resize", "pty_close", "pty_prompt"):
        return "write"
    if name in ("pty_spawn",):
        return "spawn"
    return "read"


def _scope_allows(scope: str, level: str) -> bool:
    scope = _strish(scope, "read-write") or "read-write"
    if scope == "read-only":
        return level in ("read",)
    if scope == "read-write":
        return level in ("read", "write", "spawn")
    if scope == "control":
        return level in ("read", "write", "spawn", "control")
    if scope == "admin":
        return True
    return False


def _require_session_owner(s, owner):
    if not REQUIRE_OWNER:
        return
    expected = _strish(s.get("owner"), "").strip()
    actual = _strish(owner, "").strip()
    if expected and not actual:
        raise RuntimeError("owner is required for this session")
    if expected and expected != actual:
        raise RuntimeError("session owner mismatch")


def _authorize_tool_call(name, args, session=None):
    level = _tool_access_level(name)

    if level == "admin" and not ENABLE_ADMIN_TOOLS:
        raise RuntimeError(f"tool disabled by policy: {name}")
    if level == "control" and not ENABLE_CONTROL_TOOLS:
        raise RuntimeError(f"tool disabled by policy: {name}")

    if (
        name == "pty_spawn"
        and REQUIRE_OWNER
        and not _strish(args.get("owner"), "").strip()
    ):
        raise RuntimeError("owner is required for spawn")

    if (
        name == "pty_list"
        and REQUIRE_OWNER
        and not _strish(args.get("owner"), "").strip()
    ):
        raise RuntimeError("owner is required for pty_list")

    if session is not None:
        _require_session_owner(session, args.get("owner"))
        scope = _strish(session.get("scope"), "read-write")
        if not _scope_allows(scope, level):
            raise RuntimeError(f"scope '{scope}' does not allow tool '{name}'")


def _get_session_for_args(args):
    sid = _strish((args or {}).get("session_id"), "").strip()
    if not sid:
        return None
    return sessions.get(sid)


def read_messages():
    global FRAMING
    fd = sys.stdin.fileno()
    buf = b""
    while True:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            return
        if not chunk:
            return
        buf += chunk
        if FRAMING is None:
            head = buf.lstrip()
            if head.startswith(b"Content-Length:") or b"\r\n\r\n" in buf[:512]:
                FRAMING = "lsp"
                _log("pty-runner(py) detected framing: lsp(Content-Length)")
            elif head.startswith(b"{") and (b"\n" in buf or b"\r\n" in buf):
                FRAMING = "line"
                _log("pty-runner(py) detected framing: line(NDJSON)")
        progressed = True
        while progressed:
            progressed = False
            if FRAMING in (None, "lsp"):
                header_end = buf.find(b"\r\n\r\n")
                if header_end != -1:
                    header = buf[:header_end].decode("utf-8", errors="replace")
                    rest = buf[header_end + 4 :]
                    content_length = None
                    for line in header.split("\r\n"):
                        if line.lower().startswith("content-length:"):
                            try:
                                content_length = int(line.split(":", 1)[1].strip())
                            except Exception:
                                content_length = None
                    if content_length is not None and len(rest) >= content_length:
                        body = rest[:content_length]
                        buf = rest[content_length:]
                        try:
                            yield json.loads(body.decode("utf-8", errors="replace"))
                        except Exception:
                            _log_limited(
                                "parse_lsp",
                                "failed to parse LSP JSON body:",
                                body[:200],
                            )
                        progressed = True
                        continue
            if FRAMING in (None, "line"):
                nl = buf.find(b"\n")
                if nl != -1:
                    line = buf[:nl]
                    buf = buf[nl + 1 :]
                    line = line.strip()
                    if not line:
                        progressed = True
                        continue
                    try:
                        yield json.loads(line.decode("utf-8", errors="replace"))
                    except Exception:
                        _log_limited(
                            "parse_line", "failed to parse line JSON:", line[:200]
                        )
                    progressed = True
                    continue


def send(msg: dict):
    raw = json.dumps(msg, ensure_ascii=False).encode("utf-8")
    framing = FRAMING or "lsp"
    if framing == "line":
        sys.stdout.buffer.write(raw + b"\n")
    else:
        sys.stdout.buffer.write(
            f"Content-Length: {len(raw)}\r\n\r\n".encode("ascii") + raw
        )
    sys.stdout.buffer.flush()


def ok(id_, result):
    send({"jsonrpc": "2.0", "id": id_, "result": result})


def err(id_, code, message, data=None):
    e = {"jsonrpc": "2.0", "id": id_, "error": {"code": code, "message": message}}
    if data is not None:
        e["error"]["data"] = data
    send(e)


def _intish(v, default):
    if v is None:
        return default
    try:
        return int(v)
    except Exception:
        return default


def _strish(v, default=None):
    if v is None:
        return default
    return str(v)


def _now():
    return time.time()


def set_default_cwd(cwd):
    global DEFAULT_CWD
    DEFAULT_CWD = _normalize_cwd(cwd)
    return {"ok": True, "cwd": DEFAULT_CWD}


def get_default_cwd():
    return {"cwd": _normalize_cwd(DEFAULT_CWD)}


def set_limits(
    max_output_bytes=None,
    spawn_timeout_sec=None,
    idle_timeout_sec=None,
    read_timeout_ms=None,
    rate_limit_bps=None,
    input_rate_bps=None,
):
    global \
        RING_MAX_BYTES, \
        SPAWN_TIMEOUT_SEC, \
        IDLE_TIMEOUT_SEC, \
        DEFAULT_READ_TIMEOUT_MS, \
        OUTPUT_RATE_BPS, \
        INPUT_RATE_BPS
    if max_output_bytes is not None:
        new_max = _intish(max_output_bytes, RING_MAX_BYTES)
        if new_max > 0:
            RING_MAX_BYTES = new_max
            for s in sessions.values():
                s["max_output_bytes"] = RING_MAX_BYTES
    if spawn_timeout_sec is not None:
        new_timeout = _intish(spawn_timeout_sec, SPAWN_TIMEOUT_SEC)
        SPAWN_TIMEOUT_SEC = max(0, new_timeout)
        for s in sessions.values():
            s["max_runtime_sec"] = SPAWN_TIMEOUT_SEC
    if idle_timeout_sec is not None:
        new_idle = _intish(idle_timeout_sec, IDLE_TIMEOUT_SEC)
        IDLE_TIMEOUT_SEC = max(0, new_idle)
    if read_timeout_ms is not None:
        new_read = _intish(read_timeout_ms, DEFAULT_READ_TIMEOUT_MS)
        DEFAULT_READ_TIMEOUT_MS = max(0, new_read)
    if rate_limit_bps is not None:
        new_rate = _intish(rate_limit_bps, OUTPUT_RATE_BPS)
        OUTPUT_RATE_BPS = max(0, new_rate)
        for s in sessions.values():
            s["rate_limit_bps"] = OUTPUT_RATE_BPS
    if input_rate_bps is not None:
        new_rate = _intish(input_rate_bps, INPUT_RATE_BPS)
        INPUT_RATE_BPS = max(0, new_rate)
        for s in sessions.values():
            s["input_rate_bps"] = INPUT_RATE_BPS
    return {
        "max_output_bytes": RING_MAX_BYTES,
        "spawn_timeout_sec": SPAWN_TIMEOUT_SEC,
        "idle_timeout_sec": IDLE_TIMEOUT_SEC,
        "read_timeout_ms": DEFAULT_READ_TIMEOUT_MS,
        "rate_limit_bps": OUTPUT_RATE_BPS,
        "input_rate_bps": INPUT_RATE_BPS,
    }


def get_limits():
    return {
        "max_output_bytes": RING_MAX_BYTES,
        "spawn_timeout_sec": SPAWN_TIMEOUT_SEC,
        "idle_timeout_sec": IDLE_TIMEOUT_SEC,
        "read_timeout_ms": DEFAULT_READ_TIMEOUT_MS,
        "rate_limit_bps": OUTPUT_RATE_BPS,
        "input_rate_bps": INPUT_RATE_BPS,
    }


def _server_version() -> str:
    for dist_name in ("pty-mcp", "pty_mcp"):
        try:
            return pkg_version(dist_name)
        except PackageNotFoundError:
            continue
        except Exception:
            break
    return "unknown"


sessions = {}
dangerous_confirmations = {}


def new_id():
    return f"{int(time.time() * 1000)}-{os.getpid()}-{os.urandom(4).hex()}"


def set_winsz(fd, rows, cols):
    winsz = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsz)


def set_raw(fd):
    """将 PTY 从机设置为 raw 模式，提升交互式程序兼容性。"""
    try:
        tty.setraw(fd)
    except Exception:
        pass


def _touch(s):
    s["last_active"] = _now()


def _offset_fields(buf_key: str):
    if buf_key == "stdout_buf":
        return "stdout_start_offset", "stdout_total_offset"
    if buf_key == "stderr_buf":
        return "stderr_start_offset", "stderr_total_offset"
    return "buf_start_offset", "buf_total_offset"


def _append_ring(s, data: bytes, buf_key: str = "buf", bypass_rate: bool = False):
    if not data:
        return b""
    s["bytes_read"] += len(data)
    if not bypass_rate and s.get("rate_limit_bps", 0) > 0:
        now = _now()
        window_ts = s.get("rate_window_ts", 0.0)
        if now - window_ts >= 1.0:
            s["rate_window_ts"] = now
            s["rate_window_bytes"] = 0
            s["rate_notice_ts"] = 0.0
        limit = s.get("rate_limit_bps", 0)
        window_bytes = s.get("rate_window_bytes", 0)
        if window_bytes >= limit:
            s["rate_dropped"] = s.get("rate_dropped", 0) + len(data)
            if now - s.get("rate_notice_ts", 0.0) >= 1.0:
                s["rate_notice_ts"] = now
                _append_ring(
                    s,
                    f"\n[pty-mcp] output throttled (limit={limit} bytes/sec)\n".encode(
                        "utf-8", errors="replace"
                    ),
                    buf_key=buf_key,
                    bypass_rate=True,
                )
            return b""
        remaining = limit - window_bytes
        if len(data) > remaining:
            s["rate_window_bytes"] = limit
            s["rate_dropped"] = s.get("rate_dropped", 0) + (len(data) - remaining)
            data = data[:remaining]
            if now - s.get("rate_notice_ts", 0.0) >= 1.0:
                s["rate_notice_ts"] = now
                _append_ring(
                    s,
                    f"\n[pty-mcp] output throttled (limit={limit} bytes/sec)\n".encode(
                        "utf-8", errors="replace"
                    ),
                    buf_key=buf_key,
                    bypass_rate=True,
                )
        else:
            s["rate_window_bytes"] = window_bytes + len(data)
    if not data:
        return b""
    b = s[buf_key]
    b.extend(data)
    start_field, total_field = _offset_fields(buf_key)
    s[total_field] = s.get(total_field, 0) + len(data)
    max_bytes = s.get("max_output_bytes") or RING_MAX_BYTES
    if len(b) > max_bytes:
        drop = len(b) - max_bytes
        del b[:drop]
        s[start_field] = s.get(start_field, 0) + drop
        if not s.get("truncated", False):
            s["truncated"] = True
        flag_key = f"truncated_{buf_key}"
        if not s.get(flag_key, False):
            s[flag_key] = True
            marker = f"\n[pty-mcp] output truncated (limit={max_bytes} bytes)\n".encode(
                "utf-8", errors="replace"
            )
            b.extend(marker)
            if len(b) > max_bytes:
                drop = len(b) - max_bytes
                del b[:drop]
                s[start_field] = s.get(start_field, 0) + drop
    return data


def _append_stream(s, data: bytes, stream: str = "pty"):
    appended = _append_ring(s, data, buf_key="buf", bypass_rate=False)
    if not appended:
        return
    text = appended.decode("utf-8", errors="replace")
    _append_transcript(s, text)
    if stream == "stdout":
        _append_ring(s, appended, buf_key="stdout_buf", bypass_rate=True)
    elif stream == "stderr":
        _append_ring(s, appended, buf_key="stderr_buf", bypass_rate=True)


def _drain_fd(fd, max_bytes=65536):
    """非阻塞尽量读取可用数据，作为读线程异常时的兜底。"""
    chunks = []
    total = 0
    while total < max_bytes:
        try:
            r, _, _ = select.select([fd], [], [], 0)
        except Exception:
            break
        if not r:
            break
        try:
            chunk = os.read(fd, READ_CHUNK_BYTES)
        except Exception:
            break
        if not chunk:
            break
        chunks.append(chunk)
        total += len(chunk)
    return b"".join(chunks)


def _reader_loop_fd(session_id: str, fd: int, stream: str, close_fd: bool):
    s = sessions.get(session_id)
    if not s:
        return
    proc = s["proc"]
    cond = s["cond"]
    try:
        while True:
            with cond:
                if s["closed"]:
                    return
            try:
                r, _, _ = select.select([fd], [], [], 0.2)
            except Exception:
                r = []
            if r:
                try:
                    chunk = os.read(fd, READ_CHUNK_BYTES)
                except Exception:
                    chunk = b""
                if chunk:
                    with cond:
                        _append_stream(s, chunk, stream=stream)
                        cond.notify_all()
            if proc.poll() is not None:
                if s.get("exit_reason") is None:
                    s["exit_reason"] = "exited"
                with cond:
                    cond.notify_all()
                time.sleep(0.05)
    except Exception:
        _log_limited("reader_loop", "reader loop error:", traceback.format_exc())
        with cond:
            s["closed"] = True
            cond.notify_all()
    finally:
        if close_fd:
            try:
                os.close(fd)
            except Exception:
                pass


def _cleanup_session(session_id, s):
    with s["cond"]:
        s["closed"] = True
        s["cond"].notify_all()
    proc = s["proc"]
    try:
        if proc.poll() is None:
            s["exit_reason"] = s.get("exit_reason") or "killed"
            try:
                os.killpg(s["pgid"], signal.SIGTERM)
            except Exception:
                try:
                    proc.terminate()
                except Exception:
                    pass
            deadline = _now() + 1.0
            while _now() < deadline and proc.poll() is None:
                time.sleep(0.05)
            if proc.poll() is None:
                try:
                    os.killpg(s["pgid"], signal.SIGKILL)
                except Exception:
                    try:
                        proc.kill()
                    except Exception:
                        pass
    except Exception:
        pass
    try:
        os.close(s["master_fd"])
    except Exception:
        pass
    try:
        if proc.stdout is not None:
            proc.stdout.close()
    except Exception:
        pass
    try:
        if proc.stderr is not None:
            proc.stderr.close()
    except Exception:
        pass


def gc_sessions(force=False):
    global _last_gc
    now = _now()
    _gc_dangerous_confirmations()
    if not force and (now - _last_gc) < GC_INTERVAL_SEC:
        return
    _last_gc = now
    to_close = []
    for sid, s in list(sessions.items()):
        if now - s["last_active"] > (IDLE_TIMEOUT_SEC + IDLE_GRACE_SEC):
            to_close.append(sid)
            continue
        if s["proc"].poll() is not None and now - s["last_active"] > IDLE_GRACE_SEC:
            to_close.append(sid)
    for sid in to_close:
        s = sessions.pop(sid, None)
        if s:
            _cleanup_session(sid, s)
    if len(sessions) > MAX_SESSIONS:
        exited, running = [], []
        for sid, s in sessions.items():
            if s["proc"].poll() is None:
                running.append((sid, s))
            else:
                exited.append((sid, s))
        exited.sort(key=lambda kv: kv[1]["last_active"])
        running.sort(key=lambda kv: kv[1]["last_active"])
        ordered = exited + running
        need = len(sessions) - MAX_SESSIONS
        for sid, _s in ordered[:need]:
            s = sessions.pop(sid, None)
            if s:
                _cleanup_session(sid, s)


def _normalize_cwd(cwd):
    if cwd is None:
        return None
    cwd = _strish(cwd, "")
    if not cwd:
        return None
    return os.path.realpath(os.path.expanduser(cwd))


def _infer_cwd_from_command(command: str):
    cmd = _strish(command, "").strip()
    if not cmd:
        return None
    first = None
    try:
        parts = shlex.split(cmd, posix=True)
        if parts:
            first = parts[0]
    except Exception:
        first = None
    if first is None:
        first = cmd.split()[0] if cmd.split() else None
    if not first or not first.startswith("/"):
        return None
    path = os.path.realpath(first)
    if os.path.isdir(path):
        return path
    if os.path.isfile(path):
        return os.path.dirname(path)
    return None


def _consume_from_buffer(s, buf_key: str, max_chars: int):
    b = s[buf_key]
    if not b:
        return b""
    take = min(len(b), max_chars)
    data = bytes(b[:take])
    del b[:take]
    start_field, _ = _offset_fields(buf_key)
    s[start_field] = s.get(start_field, 0) + take
    return data


def _next_chunk_id(s):
    s["chunk_seq"] = s.get("chunk_seq", 0) + 1
    return s["chunk_seq"]


def _format_read_response(s, text: str, stream: str, fmt: str, chunk_id: int):
    if fmt != "json":
        return text
    payload = {
        "chunk_id": chunk_id,
        "stream": stream,
        "text": text,
        "timestamp": _now(),
    }
    return json.dumps(payload, ensure_ascii=False)


def _ensure_session_log_dir(s):
    if not SESSION_LOG_DIR:
        return None
    base = os.path.realpath(os.path.expanduser(SESSION_LOG_DIR))
    session_dir = os.path.join(base, s["session_id"])
    try:
        os.makedirs(session_dir, exist_ok=True)
    except Exception:
        return None
    return session_dir


def _append_transcript(s, text: str):
    if not text:
        return
    session_dir = _ensure_session_log_dir(s)
    if not session_dir:
        return
    path = os.path.join(session_dir, "transcript.log")
    try:
        with open(path, "a", encoding="utf-8", errors="replace") as f:
            f.write(text)
    except Exception:
        pass


def _log_session_event(s, event: str, payload: dict):
    session_dir = _ensure_session_log_dir(s)
    if not session_dir:
        return
    path = os.path.join(session_dir, "events.jsonl")
    record = {
        "ts": _now(),
        "event": event,
        **payload,
    }
    try:
        with open(path, "a", encoding="utf-8", errors="replace") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except Exception:
        pass


def _read_from_buffer(s, buf_key: str, offset: int, max_chars: int):
    start_field, _ = _offset_fields(buf_key)
    start_offset = s.get(start_field, 0)
    b = s[buf_key]
    if offset < start_offset:
        return {"truncated": True, "text": "", "next_offset": start_offset}
    rel = offset - start_offset
    if rel > len(b):
        rel = len(b)
    take = min(len(b) - rel, max_chars)
    data = bytes(b[rel : rel + take])
    next_offset = start_offset + rel + take
    return {
        "truncated": False,
        "text": data.decode("utf-8", errors="replace"),
        "next_offset": next_offset,
    }


def _check_runtime(s):
    max_runtime = s.get("max_runtime_sec")
    if not max_runtime or max_runtime <= 0:
        return False
    if _now() - s["created_at"] <= max_runtime:
        return False
    proc = s["proc"]
    try:
        os.killpg(s["pgid"], signal.SIGTERM)
    except Exception:
        try:
            proc.terminate()
        except Exception:
            pass
    s["closed"] = True
    s["exit_reason"] = "timeout"
    _append_ring(
        s, f"\n[pty-mcp] session timed out (limit={max_runtime}s)\n".encode("utf-8")
    )
    return True


def _check_input_rate(s, size):
    limit = s.get("input_rate_bps", 0)
    if not limit or limit <= 0:
        return True
    now = _now()
    window_ts = s.get("input_window_ts", 0.0)
    if now - window_ts >= 1.0:
        s["input_window_ts"] = now
        s["input_window_bytes"] = 0
        s["input_notice_ts"] = 0.0
    window_bytes = s.get("input_window_bytes", 0)
    if window_bytes >= limit:
        s["input_dropped"] = s.get("input_dropped", 0) + size
        if now - s.get("input_notice_ts", 0.0) >= 1.0:
            s["input_notice_ts"] = now
            _append_ring(
                s,
                f"\n[pty-mcp] input throttled (limit={limit} bytes/sec)\n".encode(
                    "utf-8", errors="replace"
                ),
                buf_key="buf",
                bypass_rate=True,
            )
        return False
    remaining = limit - window_bytes
    if size > remaining:
        s["input_window_bytes"] = limit
        s["input_dropped"] = s.get("input_dropped", 0) + (size - remaining)
        if now - s.get("input_notice_ts", 0.0) >= 1.0:
            s["input_notice_ts"] = now
            _append_ring(
                s,
                f"\n[pty-mcp] input throttled (limit={limit} bytes/sec)\n".encode(
                    "utf-8", errors="replace"
                ),
                buf_key="buf",
                bypass_rate=True,
            )
        return False
    s["input_window_bytes"] = window_bytes + size
    return True


def pty_spawn(
    command,
    cwd=None,
    cols=120,
    rows=30,
    separate_streams=False,
    tag=None,
    owner=None,
    scope=None,
    max_output_bytes=None,
    spawn_timeout_sec=None,
    rate_limit_bps=None,
    input_rate_bps=None,
    read_timeout_ms=None,
    env_override=None,
    backend=None,
    dangerous_confirmed=False,
    dangerous_justification=None,
    dangerous_confirm_token=None,
):
    gc_sessions()
    if len(sessions) >= MAX_SESSIONS:
        raise RuntimeError(f"too many sessions (max {MAX_SESSIONS})")
    command = _strish(command, "")
    if not command:
        raise RuntimeError("command is required")
    backend = _strish(backend, DEFAULT_BACKEND) or DEFAULT_BACKEND
    if backend != "subprocess":
        raise RuntimeError(f"unsupported backend: {backend}")
    matches = _is_dangerous_command(command)
    confirmation_mode = "none"
    if matches:
        token = _strish(dangerous_confirm_token, "").strip()
        if token:
            _consume_dangerous_confirmation(
                token=token,
                command=command,
                owner=owner,
                scope=scope,
            )
            confirmation_mode = "token"
        elif DANGEROUS_LEGACY_MODE:
            legacy_justification = _strish(dangerous_justification, "").strip()
            if not dangerous_confirmed and not legacy_justification:
                raise RuntimeError(
                    "dangerous command detected; use confirm_dangerous_command"
                )
            confirmation_mode = "legacy"
            _log("dangerous legacy confirmation path used", level="warn")
        else:
            raise RuntimeError(
                "dangerous command detected; confirmation token required"
            )
    cols = _intish(cols, 120)
    rows = _intish(rows, 30)
    cwd = _normalize_cwd(cwd)
    inferred_cwd = _infer_cwd_from_command(command)
    effective_cwd = cwd or _normalize_cwd(DEFAULT_CWD) or inferred_cwd or os.getcwd()
    master_fd, slave_fd = pty.openpty()
    try:
        set_winsz(slave_fd, rows, cols)
    except Exception:
        pass
    # 尝试启用 raw 模式，改善交互式安装器的 TTY 判断/行为
    set_raw(slave_fd)
    fl = fcntl.fcntl(master_fd, fcntl.F_GETFL)
    fcntl.fcntl(master_fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    env = os.environ.copy()
    if isinstance(env_override, dict):
        for k, v in env_override.items():
            if k is None:
                continue
            env[str(k)] = "" if v is None else str(v)
    # 透传/补齐终端环境变量，尽量模拟真实 TTY 环境
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")
    env.setdefault("LANG", "C.UTF-8")
    env.setdefault("LC_ALL", env.get("LANG", "C.UTF-8"))
    separate_streams = bool(separate_streams)
    stdout_target = slave_fd
    stderr_target = slave_fd
    if separate_streams:
        stdout_target = subprocess.PIPE
        stderr_target = subprocess.PIPE
    proc = subprocess.Popen(
        ["bash", "-lc", command],
        stdin=slave_fd,
        stdout=stdout_target,
        stderr=stderr_target,
        cwd=effective_cwd,
        env=env,
        start_new_session=True,
        close_fds=True,
    )
    os.close(slave_fd)
    try:
        pgid = os.getpgid(proc.pid)
    except Exception:
        pgid = proc.pid
    sid = new_id()
    cond = threading.Condition()
    max_output_bytes = _intish(max_output_bytes, RING_MAX_BYTES)
    if max_output_bytes <= 0:
        max_output_bytes = RING_MAX_BYTES
    max_runtime_sec = _intish(spawn_timeout_sec, SPAWN_TIMEOUT_SEC)
    if max_runtime_sec < 0:
        max_runtime_sec = 0
    rate_limit_bps = _intish(rate_limit_bps, OUTPUT_RATE_BPS)
    if rate_limit_bps < 0:
        rate_limit_bps = 0
    input_rate_bps = _intish(input_rate_bps, INPUT_RATE_BPS)
    if input_rate_bps < 0:
        input_rate_bps = 0
    read_timeout_ms = _intish(read_timeout_ms, DEFAULT_READ_TIMEOUT_MS)
    if read_timeout_ms < 0:
        read_timeout_ms = DEFAULT_READ_TIMEOUT_MS
    scope = _strish(scope, "read-write") or "read-write"
    s = {
        "master_fd": master_fd,
        "proc": proc,
        "pid": proc.pid,
        "pgid": pgid,
        "created_at": _now(),
        "last_active": _now(),
        "command": command,
        "cwd": effective_cwd,
        "cols": cols,
        "rows": rows,
        "buf": bytearray(),
        "stdout_buf": bytearray(),
        "stderr_buf": bytearray(),
        "buf_start_offset": 0,
        "buf_total_offset": 0,
        "stdout_start_offset": 0,
        "stdout_total_offset": 0,
        "stderr_start_offset": 0,
        "stderr_total_offset": 0,
        "closed": False,
        "cond": cond,
        "max_output_bytes": max_output_bytes,
        "max_runtime_sec": max_runtime_sec,
        "rate_limit_bps": rate_limit_bps,
        "rate_window_ts": 0.0,
        "rate_window_bytes": 0,
        "rate_notice_ts": 0.0,
        "rate_dropped": 0,
        "input_rate_bps": input_rate_bps,
        "input_window_ts": 0.0,
        "input_window_bytes": 0,
        "input_notice_ts": 0.0,
        "input_dropped": 0,
        "separate_streams": separate_streams,
        "tag": _strish(tag, None),
        "owner": _strish(owner, None),
        "scope": scope,
        "read_timeout_ms": read_timeout_ms,
        "chunk_seq": 0,
        "session_id": sid,
        "env_override": env_override if isinstance(env_override, dict) else None,
        "truncated": False,
        # 统计数据
        "bytes_read": 0,
        "bytes_written": 0,
    }
    sessions[sid] = s
    _log_session_event(
        s,
        "spawn",
        {
            "command": command,
            "cwd": effective_cwd,
            "cols": cols,
            "rows": rows,
            "tag": s.get("tag"),
            "owner": s.get("owner"),
            "scope": s.get("scope"),
            "backend": backend,
            "dangerous": bool(matches),
            "dangerous_matches": matches,
            "confirmation_mode": confirmation_mode,
            "dangerous_confirm_token_present": bool(
                _strish(dangerous_confirm_token, "").strip()
            ),
            "dangerous_justification_present": bool(
                _strish(dangerous_justification, "").strip()
            ),
        },
    )
    threads = []
    if separate_streams and proc.stdout is not None and proc.stderr is not None:
        t_out = threading.Thread(
            target=_reader_loop_fd,
            args=(sid, proc.stdout.fileno(), "stdout", True),
            daemon=True,
        )
        t_err = threading.Thread(
            target=_reader_loop_fd,
            args=(sid, proc.stderr.fileno(), "stderr", True),
            daemon=True,
        )
        threads.extend([t_out, t_err])
        t_out.start()
        t_err.start()
    else:
        t = threading.Thread(
            target=_reader_loop_fd, args=(sid, master_fd, "pty", False), daemon=True
        )
        threads.append(t)
        t.start()
    s["reader_threads"] = threads
    return sid


def pty_read(session_id, max_chars=DEFAULT_MAX_CHARS, timeout_ms=None, format=None):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    if _check_runtime(s):
        return ""
    _touch(s)
    max_chars = _intish(max_chars, DEFAULT_MAX_CHARS)
    if timeout_ms is None:
        timeout_ms = s.get("read_timeout_ms", DEFAULT_READ_TIMEOUT_MS)
    timeout_ms = _intish(timeout_ms, DEFAULT_READ_TIMEOUT_MS)
    deadline = (
        _now() + (timeout_ms / 1000.0) if timeout_ms and timeout_ms > 0 else _now()
    )
    with s["cond"]:
        while not s["buf"] and not s["closed"] and timeout_ms and timeout_ms > 0:
            remaining = deadline - _now()
            if remaining <= 0:
                break
            s["cond"].wait(timeout=min(0.2, remaining))
        if not s["buf"]:
            direct = _drain_fd(s["master_fd"])
            if direct:
                _append_stream(s, direct, stream="pty")
        if not s["buf"]:
            return ""
        data = _consume_from_buffer(s, "buf", max_chars)
    text = data.decode("utf-8", errors="replace")
    chunk_id = _next_chunk_id(s)
    return _format_read_response(s, text, "pty", format or "text", chunk_id)


def pty_read_stdout(
    session_id, max_chars=DEFAULT_MAX_CHARS, timeout_ms=None, format=None
):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    if _check_runtime(s):
        return ""
    _touch(s)
    max_chars = _intish(max_chars, DEFAULT_MAX_CHARS)
    if timeout_ms is None:
        timeout_ms = s.get("read_timeout_ms", DEFAULT_READ_TIMEOUT_MS)
    timeout_ms = _intish(timeout_ms, DEFAULT_READ_TIMEOUT_MS)
    deadline = (
        _now() + (timeout_ms / 1000.0) if timeout_ms and timeout_ms > 0 else _now()
    )
    with s["cond"]:
        while not s["stdout_buf"] and not s["closed"] and timeout_ms and timeout_ms > 0:
            remaining = deadline - _now()
            if remaining <= 0:
                break
            s["cond"].wait(timeout=min(0.2, remaining))
        if not s["stdout_buf"]:
            return ""
        data = _consume_from_buffer(s, "stdout_buf", max_chars)
    text = data.decode("utf-8", errors="replace")
    chunk_id = _next_chunk_id(s)
    return _format_read_response(s, text, "stdout", format or "text", chunk_id)


def pty_read_stderr(
    session_id, max_chars=DEFAULT_MAX_CHARS, timeout_ms=None, format=None
):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    if _check_runtime(s):
        return ""
    _touch(s)
    max_chars = _intish(max_chars, DEFAULT_MAX_CHARS)
    if timeout_ms is None:
        timeout_ms = s.get("read_timeout_ms", DEFAULT_READ_TIMEOUT_MS)
    timeout_ms = _intish(timeout_ms, DEFAULT_READ_TIMEOUT_MS)
    deadline = (
        _now() + (timeout_ms / 1000.0) if timeout_ms and timeout_ms > 0 else _now()
    )
    with s["cond"]:
        while not s["stderr_buf"] and not s["closed"] and timeout_ms and timeout_ms > 0:
            remaining = deadline - _now()
            if remaining <= 0:
                break
            s["cond"].wait(timeout=min(0.2, remaining))
        if not s["stderr_buf"]:
            return ""
        data = _consume_from_buffer(s, "stderr_buf", max_chars)
    text = data.decode("utf-8", errors="replace")
    chunk_id = _next_chunk_id(s)
    return _format_read_response(s, text, "stderr", format or "text", chunk_id)


def pty_read_at(session_id, offset=0, max_chars=DEFAULT_MAX_CHARS, stream=None):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    if _check_runtime(s):
        return {"truncated": True, "text": "", "next_offset": offset}
    _touch(s)
    max_chars = _intish(max_chars, DEFAULT_MAX_CHARS)
    offset = _intish(offset, 0)
    if offset < 0:
        offset = 0
    key = "buf"
    if stream == "stdout":
        key = "stdout_buf"
    elif stream == "stderr":
        key = "stderr_buf"
    res = _read_from_buffer(s, key, offset, max_chars)
    res["chunk_id"] = _next_chunk_id(s)
    res["stream"] = stream or "pty"
    res["timestamp"] = _now()
    return res


def pty_read_until(
    session_id, pattern: str, timeout_ms=10000, max_chars=DEFAULT_MAX_CHARS, regex=False
):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    _touch(s)
    pattern = _strish(pattern, "")
    if not pattern:
        raise RuntimeError("pattern is required")
    timeout_ms = _intish(timeout_ms, 10000)
    if READ_UNTIL_MAX_MS and timeout_ms > READ_UNTIL_MAX_MS:
        timeout_ms = READ_UNTIL_MAX_MS
    max_chars = _intish(max_chars, DEFAULT_MAX_CHARS)
    regex = bool(regex)
    deadline = _now() + (timeout_ms / 1000.0)
    collected = bytearray()
    rx = re.compile(pattern) if regex else None

    def _matches(text: str) -> bool:
        return rx.search(text) is not None if rx else (pattern in text)

    while True:
        step_timeout = int(min(300, max(0, (deadline - _now()) * 1000)))
        chunk = pty_read(session_id, max_chars=max_chars, timeout_ms=step_timeout)
        if chunk:
            collected.extend(
                chunk.encode("utf-8", errors="replace")
                if isinstance(chunk, str)
                else chunk
            )
            if len(collected) > max_chars:
                collected = collected[-max_chars:]
            text = collected.decode("utf-8", errors="replace")
            if _matches(text):
                return {
                    "matched": True,
                    "text": text,
                    "chunk_id": _next_chunk_id(s),
                    "stream": "pty",
                }
        if _now() >= deadline:
            text = collected.decode("utf-8", errors="replace")
            return {
                "matched": False,
                "text": text,
                "chunk_id": _next_chunk_id(s),
                "stream": "pty",
            }


def pty_read_until_any(
    session_id, patterns, timeout_ms=10000, max_chars=DEFAULT_MAX_CHARS, regex=False
):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    _touch(s)
    patterns = patterns or []
    patterns = [str(p) for p in patterns if p is not None]
    if not patterns:
        raise RuntimeError("patterns is required")
    timeout_ms = _intish(timeout_ms, 10000)
    if READ_UNTIL_MAX_MS and timeout_ms > READ_UNTIL_MAX_MS:
        timeout_ms = READ_UNTIL_MAX_MS
    max_chars = _intish(max_chars, DEFAULT_MAX_CHARS)
    regex = bool(regex)
    deadline = _now() + (timeout_ms / 1000.0)
    collected = bytearray()
    rx_list = [re.compile(p) for p in patterns] if regex else None

    def _matches(text: str):
        if rx_list:
            for idx, rx in enumerate(rx_list):
                if rx.search(text) is not None:
                    return idx
            return None
        for idx, p in enumerate(patterns):
            if p in text:
                return idx
        return None

    while True:
        step_timeout = int(min(300, max(0, (deadline - _now()) * 1000)))
        chunk = pty_read(session_id, max_chars=max_chars, timeout_ms=step_timeout)
        if chunk:
            collected.extend(
                chunk.encode("utf-8", errors="replace")
                if isinstance(chunk, str)
                else chunk
            )
            if len(collected) > max_chars:
                collected = collected[-max_chars:]
            text = collected.decode("utf-8", errors="replace")
            idx = _matches(text)
            if idx is not None:
                return {
                    "matched": True,
                    "pattern": patterns[idx],
                    "text": text,
                    "chunk_id": _next_chunk_id(s),
                    "stream": "pty",
                }
        if _now() >= deadline:
            text = collected.decode("utf-8", errors="replace")
            return {
                "matched": False,
                "pattern": None,
                "text": text,
                "chunk_id": _next_chunk_id(s),
                "stream": "pty",
            }


def pty_read_quiescent(
    session_id,
    quiescence_ms=None,
    timeout_ms=10000,
    max_chars=DEFAULT_MAX_CHARS,
    format=None,
):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    if _check_runtime(s):
        return ""
    _touch(s)
    max_chars = _intish(max_chars, DEFAULT_MAX_CHARS)
    timeout_ms = _intish(timeout_ms, 10000)
    quiescence_ms = _intish(quiescence_ms, QUIESCENCE_MS)
    if quiescence_ms < 0:
        quiescence_ms = QUIESCENCE_MS
    deadline = _now() + (timeout_ms / 1000.0)
    quiet_deadline = None
    collected = bytearray()
    while True:
        step_timeout = int(min(300, max(0, (deadline - _now()) * 1000)))
        chunk = pty_read(session_id, max_chars=max_chars, timeout_ms=step_timeout)
        if chunk:
            collected.extend(
                chunk.encode("utf-8", errors="replace")
                if isinstance(chunk, str)
                else chunk
            )
            if len(collected) > max_chars:
                collected = collected[-max_chars:]
            quiet_deadline = _now() + (quiescence_ms / 1000.0)
        if quiet_deadline is not None and _now() >= quiet_deadline:
            break
        if _now() >= deadline:
            break
    text = collected.decode("utf-8", errors="replace")
    chunk_id = _next_chunk_id(s)
    return _format_read_response(s, text, "pty", format or "text", chunk_id)


def pty_prompt(
    session_id,
    data: str,
    patterns,
    timeout_ms=10000,
    max_chars=DEFAULT_MAX_CHARS,
    regex=False,
):
    pty_write(session_id, _strish(data, ""))
    return pty_read_until_any(
        session_id,
        patterns=patterns,
        regex=regex,
        timeout_ms=timeout_ms,
        max_chars=max_chars,
    )


def confirm_dangerous_command(
    command: str, justification: str = "", owner=None, scope=None
):
    matches = _is_dangerous_command(command)
    if not matches:
        return {"ok": True, "dangerous": False, "matches": []}
    justification = _strish(justification, "").strip()
    if not justification:
        return {
            "ok": False,
            "dangerous": True,
            "matches": matches,
            "error": "justification required",
        }
    item = _issue_dangerous_confirmation(
        command=command,
        justification=justification,
        owner=owner,
        scope=scope,
    )
    return {
        "ok": True,
        "dangerous": True,
        "matches": matches,
        "confirm_token": item["token"],
        "expires_at": item["expires_at"],
    }


def pty_write(session_id, data: str):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    if _check_runtime(s):
        return
    if s.get("scope") == "read-only":
        raise RuntimeError("read-only session")
    _touch(s)
    data = _strish(data, "")
    payload = data.encode("utf-8", errors="replace")
    if not _check_input_rate(s, len(payload)):
        return
    os.write(s["master_fd"], payload)
    # 记录累计写入字节数，便于诊断交互输入
    s["bytes_written"] += len(payload)
    _log_session_event(s, "write", {"bytes": len(payload)})


def pty_resize(session_id, cols: int, rows: int):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    _touch(s)
    cols = _intish(cols, s["cols"])
    rows = _intish(rows, s["rows"])
    s["cols"], s["rows"] = cols, rows
    try:
        set_winsz(s["master_fd"], rows, cols)
    except Exception:
        pass


def pty_close(session_id):
    s = sessions.pop(session_id, None)
    if s:
        _cleanup_session(session_id, s)


def pty_close_all():
    for sid in list(sessions.keys()):
        try:
            pty_close(sid)
        except Exception:
            pass


def pty_status(session_id):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    _check_runtime(s)
    _touch(s)
    proc = s["proc"]
    code = proc.poll()
    return {
        "session_id": session_id,
        "pid": s["pid"],
        "pgid": s["pgid"],
        "running": code is None,
        "exit_code": code,
        "command": s["command"],
        "cwd": s["cwd"],
        "cols": s["cols"],
        "rows": s["rows"],
        "tag": s.get("tag"),
        "owner": s.get("owner"),
        "separate_streams": s.get("separate_streams", False),
        "created_at": s["created_at"],
        "last_active": s["last_active"],
        "exit_reason": s.get("exit_reason"),
        "buffer_bytes": len(s["buf"]),
        "stdout_buffer_bytes": len(s["stdout_buf"]),
        "stderr_buffer_bytes": len(s["stderr_buf"]),
        "buf_start_offset": s.get("buf_start_offset", 0),
        "buf_total_offset": s.get("buf_total_offset", 0),
        "stdout_start_offset": s.get("stdout_start_offset", 0),
        "stdout_total_offset": s.get("stdout_total_offset", 0),
        "stderr_start_offset": s.get("stderr_start_offset", 0),
        "stderr_total_offset": s.get("stderr_total_offset", 0),
        "max_output_bytes": s.get("max_output_bytes"),
        "max_runtime_sec": s.get("max_runtime_sec"),
        "rate_limit_bps": s.get("rate_limit_bps"),
        "rate_dropped": s.get("rate_dropped", 0),
        "input_rate_bps": s.get("input_rate_bps"),
        "input_dropped": s.get("input_dropped", 0),
        "truncated": s.get("truncated", False),
        "bytes_read": s["bytes_read"],
        "bytes_written": s["bytes_written"],
    }


def pty_wait(session_id, timeout_ms=10000):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    _check_runtime(s)
    _touch(s)
    timeout_ms = _intish(timeout_ms, 10000)
    proc = s["proc"]
    deadline = _now() + (timeout_ms / 1000.0)
    while _now() < deadline:
        code = proc.poll()
        if code is not None:
            return {
                "running": False,
                "exit_code": code,
                "exit_reason": s.get("exit_reason"),
            }
        time.sleep(0.05)
    return {"running": True, "exit_code": None, "exit_reason": s.get("exit_reason")}


_SIGMAP = {
    "SIGINT": signal.SIGINT,
    "SIGTERM": signal.SIGTERM,
    "SIGKILL": signal.SIGKILL,
    "SIGHUP": signal.SIGHUP,
    "SIGQUIT": signal.SIGQUIT,
}


def pty_signal(session_id, sig: str):
    gc_sessions()
    s = sessions.get(session_id)
    if not s:
        raise RuntimeError("unknown session_id")
    if _check_runtime(s):
        return {"ok": False, "error": "session timed out"}
    _touch(s)
    sig = _strish(sig, "SIGTERM").upper()
    if not sig.startswith("SIG"):
        sig = "SIG" + sig
    if sig not in _SIGMAP:
        raise RuntimeError(f"unsupported signal: {sig}")
    proc = s["proc"]
    if proc.poll() is not None:
        return {"ok": True, "note": "already exited", "exit_code": proc.poll()}
    try:
        os.killpg(s["pgid"], _SIGMAP[sig])
        s["exit_reason"] = "signaled"
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True}


def pty_list(tag=None, owner=None):
    gc_sessions()
    out = []
    for sid, s in sessions.items():
        if tag is not None and s.get("tag") != tag:
            continue
        if owner is not None and s.get("owner") != owner:
            continue
        code = s["proc"].poll()
        out.append(
            {
                "session_id": sid,
                "pid": s["pid"],
                "pgid": s["pgid"],
                "running": code is None,
                "exit_code": code,
                "command": s["command"],
                "cwd": s["cwd"],
                "cols": s["cols"],
                "rows": s["rows"],
                "tag": s.get("tag"),
                "owner": s.get("owner"),
                "created_at": s["created_at"],
                "last_active": s["last_active"],
                "buffer_bytes": len(s["buf"]),
                "bytes_read": s["bytes_read"],
                "bytes_written": s["bytes_written"],
            }
        )
    out.sort(key=lambda x: x["last_active"])
    return out


def pty_metrics():
    gc_sessions()
    total = len(sessions)
    running = 0
    bytes_read_total = 0
    bytes_written_total = 0
    truncated = 0
    rate_dropped_total = 0
    for s in sessions.values():
        if s["proc"].poll() is None:
            running += 1
        bytes_read_total += s.get("bytes_read", 0)
        bytes_written_total += s.get("bytes_written", 0)
        rate_dropped_total += s.get("rate_dropped", 0)
        if s.get("truncated"):
            truncated += 1
    return {
        "uptime_sec": int(_now() - _server_started),
        "session_count": total,
        "running_count": running,
        "max_sessions": MAX_SESSIONS,
        "bytes_read_total": bytes_read_total,
        "bytes_written_total": bytes_written_total,
        "rate_dropped_total": rate_dropped_total,
        "input_dropped_total": sum(
            s.get("input_dropped", 0) for s in sessions.values()
        ),
        "truncated_sessions": truncated,
    }


def pty_health():
    return {
        "ok": True,
        "uptime_sec": int(_now() - _server_started),
        "session_count": len(sessions),
        "max_sessions": MAX_SESSIONS,
    }


TOOLS = [
    {
        "name": "pty_spawn",
        "description": "Spawn a command in a pseudo-terminal. Returns session_id.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "command": {"type": "string"},
                "cwd": {"type": ["string", "null"]},
                "cols": {"type": ["integer", "string", "null"]},
                "rows": {"type": ["integer", "string", "null"]},
                "separate_streams": {"type": ["boolean", "null"]},
                "tag": {"type": ["string", "null"]},
                "owner": {"type": ["string", "null"]},
                "scope": {"type": ["string", "null"]},
                "max_output_bytes": {"type": ["integer", "string", "null"]},
                "spawn_timeout_sec": {"type": ["integer", "string", "null"]},
                "rate_limit_bps": {"type": ["integer", "string", "null"]},
                "input_rate_bps": {"type": ["integer", "string", "null"]},
                "read_timeout_ms": {"type": ["integer", "string", "null"]},
                "env": {"type": ["object", "null"]},
                "backend": {"type": ["string", "null"]},
                "dangerous_confirmed": {"type": ["boolean", "null"]},
                "dangerous_justification": {"type": ["string", "null"]},
                "dangerous_confirm_token": {"type": ["string", "null"]},
            },
            "required": ["command"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_read",
        "description": "Read and consume output from the PTY session ring buffer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
                "format": {"type": ["string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_read_stdout",
        "description": "Read and consume stdout buffer from the PTY session.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
                "format": {"type": ["string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_read_stderr",
        "description": "Read and consume stderr buffer from the PTY session.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
                "format": {"type": ["string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_read_at",
        "description": "Read output from offset without consuming.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "offset": {"type": ["integer", "string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
                "stream": {"type": ["string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_read_until",
        "description": "Read until substring/regex is matched or timeout.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "pattern": {"type": "string"},
                "regex": {"type": ["boolean", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
            },
            "required": ["session_id", "pattern"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_read_until_any",
        "description": "Read until any pattern matches or timeout.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "patterns": {"type": "array", "items": {"type": "string"}},
                "regex": {"type": ["boolean", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
            },
            "required": ["session_id", "patterns"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_read_quiescent",
        "description": "Read until output is silent for quiescence_ms or timeout.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "quiescence_ms": {"type": ["integer", "string", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
                "format": {"type": ["string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_prompt",
        "description": "Write input then read until any pattern matches.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "data": {"type": "string"},
                "patterns": {"type": "array", "items": {"type": "string"}},
                "regex": {"type": ["boolean", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
                "max_chars": {"type": ["integer", "string", "null"]},
            },
            "required": ["session_id", "data", "patterns"],
            "additionalProperties": False,
        },
    },
    {
        "name": "confirm_dangerous_command",
        "description": "Confirm a dangerous command with justification.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "command": {"type": "string"},
                "justification": {"type": ["string", "null"]},
                "owner": {"type": ["string", "null"]},
                "scope": {"type": ["string", "null"]},
            },
            "required": ["command"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_write",
        "description": "Write text to the PTY session (include \\n for Enter).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "data": {"type": "string"},
            },
            "required": ["session_id", "data"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_resize",
        "description": "Resize the PTY session.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "cols": {"type": ["integer", "string"]},
                "rows": {"type": ["integer", "string"]},
            },
            "required": ["session_id", "cols", "rows"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_close",
        "description": "Close the PTY session.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_close_all",
        "description": "Close all PTY sessions.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_status",
        "description": "Get status of the session process and metadata.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_wait",
        "description": "Wait for process exit up to timeout_ms.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "timeout_ms": {"type": ["integer", "string", "null"]},
            },
            "required": ["session_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_signal",
        "description": "Send a signal to the session process group.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "owner": {"type": ["string", "null"]},
                "sig": {"type": "string"},
            },
            "required": ["session_id", "sig"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_list",
        "description": "List all sessions.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tag": {"type": ["string", "null"]},
                "owner": {"type": ["string", "null"]},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "set_default_cwd",
        "description": "Set default working directory for future spawns.",
        "inputSchema": {
            "type": "object",
            "properties": {"cwd": {"type": ["string", "null"]}},
            "additionalProperties": False,
        },
    },
    {
        "name": "get_default_cwd",
        "description": "Get default working directory for future spawns.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "set_limits",
        "description": "Update runtime limits.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "max_output_bytes": {"type": ["integer", "string", "null"]},
                "spawn_timeout_sec": {"type": ["integer", "string", "null"]},
                "idle_timeout_sec": {"type": ["integer", "string", "null"]},
                "read_timeout_ms": {"type": ["integer", "string", "null"]},
                "rate_limit_bps": {"type": ["integer", "string", "null"]},
                "input_rate_bps": {"type": ["integer", "string", "null"]},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "get_limits",
        "description": "Get runtime limits.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_metrics",
        "description": "Get aggregate metrics.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
    {
        "name": "pty_health",
        "description": "Get health status.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "additionalProperties": False,
        },
    },
]


def _tool_visible(name: str) -> bool:
    if name in (
        "pty_close_all",
        "set_limits",
        "set_default_cwd",
        "get_limits",
        "get_default_cwd",
        "pty_metrics",
        "pty_health",
    ):
        return ENABLE_ADMIN_TOOLS
    if name in ("pty_signal",):
        return ENABLE_CONTROL_TOOLS
    return True


TOOLS = [tool for tool in TOOLS if _tool_visible(tool["name"])]


def handle_tools_call(name, args):
    args = args or {}
    session = _get_session_for_args(args)
    if _strish(args.get("session_id"), "").strip() and session is None:
        raise RuntimeError("unknown session_id")
    _authorize_tool_call(name, args, session=session)
    if name == "pty_spawn":
        cols = _intish(args.get("cols"), 120)
        rows = _intish(args.get("rows"), 30)
        sid = pty_spawn(
            args.get("command"),
            cwd=args.get("cwd"),
            cols=cols,
            rows=rows,
            separate_streams=args.get("separate_streams", False),
            tag=args.get("tag"),
            owner=args.get("owner"),
            scope=args.get("scope"),
            max_output_bytes=args.get("max_output_bytes"),
            spawn_timeout_sec=args.get("spawn_timeout_sec"),
            rate_limit_bps=args.get("rate_limit_bps"),
            input_rate_bps=args.get("input_rate_bps"),
            read_timeout_ms=args.get("read_timeout_ms"),
            env_override=args.get("env"),
            backend=args.get("backend"),
            dangerous_confirmed=args.get("dangerous_confirmed", False),
            dangerous_justification=args.get("dangerous_justification"),
            dangerous_confirm_token=args.get("dangerous_confirm_token"),
        )
        if _SPAWN_META:
            s = sessions.get(sid)
            meta = {
                "session_id": sid,
                "pid": s["pid"] if s else None,
                "pgid": s["pgid"] if s else None,
                "cwd": s["cwd"] if s else None,
                "cols": s["cols"] if s else None,
                "rows": s["rows"] if s else None,
                "tag": s.get("tag") if s else None,
                "owner": s.get("owner") if s else None,
                "separate_streams": s.get("separate_streams") if s else None,
                "max_output_bytes": s.get("max_output_bytes") if s else None,
                "max_runtime_sec": s.get("max_runtime_sec") if s else None,
                "rate_limit_bps": s.get("rate_limit_bps") if s else None,
                "created_at": s["created_at"] if s else None,
            }
            text = json.dumps(meta, ensure_ascii=False)
        else:
            text = sid
        return {"content": [{"type": "text", "text": text}]}
    if name == "pty_read":
        return {
            "content": [
                {
                    "type": "text",
                    "text": pty_read(
                        args.get("session_id"),
                        max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                        timeout_ms=args.get("timeout_ms"),
                        format=args.get("format"),
                    ),
                }
            ]
        }
    if name == "pty_read_stdout":
        return {
            "content": [
                {
                    "type": "text",
                    "text": pty_read_stdout(
                        args.get("session_id"),
                        max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                        timeout_ms=args.get("timeout_ms"),
                        format=args.get("format"),
                    ),
                }
            ]
        }
    if name == "pty_read_stderr":
        return {
            "content": [
                {
                    "type": "text",
                    "text": pty_read_stderr(
                        args.get("session_id"),
                        max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                        timeout_ms=args.get("timeout_ms"),
                        format=args.get("format"),
                    ),
                }
            ]
        }
    if name == "pty_read_at":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_read_at(
                            args.get("session_id"),
                            offset=args.get("offset", 0),
                            max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                            stream=args.get("stream"),
                        ),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "pty_read_until":
        pattern = _strish(args.get("pattern"), "")
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_read_until(
                            args.get("session_id"),
                            pattern=pattern,
                            regex=args.get("regex", False),
                            timeout_ms=args.get("timeout_ms", 10000),
                            max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                        ),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "pty_read_until_any":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_read_until_any(
                            args.get("session_id"),
                            patterns=args.get("patterns"),
                            regex=args.get("regex", False),
                            timeout_ms=args.get("timeout_ms", 10000),
                            max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                        ),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "pty_read_quiescent":
        return {
            "content": [
                {
                    "type": "text",
                    "text": pty_read_quiescent(
                        args.get("session_id"),
                        quiescence_ms=args.get("quiescence_ms"),
                        timeout_ms=args.get("timeout_ms", 10000),
                        max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                        format=args.get("format"),
                    ),
                }
            ]
        }
    if name == "pty_prompt":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_prompt(
                            args.get("session_id"),
                            _strish(args.get("data"), ""),
                            patterns=args.get("patterns"),
                            regex=args.get("regex", False),
                            timeout_ms=args.get("timeout_ms", 10000),
                            max_chars=args.get("max_chars", DEFAULT_MAX_CHARS),
                        ),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "confirm_dangerous_command":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        confirm_dangerous_command(
                            _strish(args.get("command"), ""),
                            _strish(args.get("justification"), ""),
                            owner=_strish(args.get("owner"), ""),
                            scope=_strish(args.get("scope"), ""),
                        ),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "pty_write":
        pty_write(args.get("session_id"), _strish(args.get("data"), ""))
        return {"content": [{"type": "text", "text": "ok"}]}
    if name == "pty_resize":
        cols = _intish(args.get("cols"), 120)
        rows = _intish(args.get("rows"), 30)
        pty_resize(args.get("session_id"), cols, rows)
        return {"content": [{"type": "text", "text": "ok"}]}
    if name == "pty_close":
        pty_close(args.get("session_id"))
        return {"content": [{"type": "text", "text": "ok"}]}
    if name == "pty_close_all":
        pty_close_all()
        return {"content": [{"type": "text", "text": "ok"}]}
    if name == "pty_status":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_status(args.get("session_id")), ensure_ascii=False
                    ),
                }
            ]
        }
    if name == "pty_wait":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_wait(args.get("session_id"), args.get("timeout_ms", 10000)),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "pty_signal":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_signal(
                            args.get("session_id"), _strish(args.get("sig"), "SIGTERM")
                        ),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "pty_list":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        pty_list(tag=args.get("tag"), owner=args.get("owner")),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "set_default_cwd":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        set_default_cwd(args.get("cwd")), ensure_ascii=False
                    ),
                }
            ]
        }
    if name == "get_default_cwd":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(get_default_cwd(), ensure_ascii=False),
                }
            ]
        }
    if name == "set_limits":
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(
                        set_limits(
                            max_output_bytes=args.get("max_output_bytes"),
                            spawn_timeout_sec=args.get("spawn_timeout_sec"),
                            idle_timeout_sec=args.get("idle_timeout_sec"),
                            read_timeout_ms=args.get("read_timeout_ms"),
                            rate_limit_bps=args.get("rate_limit_bps"),
                            input_rate_bps=args.get("input_rate_bps"),
                        ),
                        ensure_ascii=False,
                    ),
                }
            ]
        }
    if name == "get_limits":
        return {
            "content": [
                {"type": "text", "text": json.dumps(get_limits(), ensure_ascii=False)}
            ]
        }
    if name == "pty_metrics":
        return {
            "content": [
                {"type": "text", "text": json.dumps(pty_metrics(), ensure_ascii=False)}
            ]
        }
    if name == "pty_health":
        return {
            "content": [
                {"type": "text", "text": json.dumps(pty_health(), ensure_ascii=False)}
            ]
        }
    raise RuntimeError("unknown tool")


def shutdown():
    try:
        pty_close_all()
    except Exception:
        pass


def _sig_handler(signum, _frame):
    shutdown()
    sys.exit(0)


def main():
    _log("pty-runner(py) boot")
    signal.signal(signal.SIGTERM, _sig_handler)
    signal.signal(signal.SIGINT, _sig_handler)
    try:
        for msg in read_messages():
            try:
                method, id_, params = (
                    msg.get("method"),
                    msg.get("id"),
                    msg.get("params") or {},
                )
                if method in ("initialized",):
                    continue
                if method == "initialize":
                    ok(
                        id_,
                        {
                            "protocolVersion": params.get("protocolVersion")
                            or "2024-11-05",
                            "capabilities": {"tools": {}},
                            "serverInfo": {
                                "name": "pty-mcp",
                                "version": _server_version(),
                            },
                        },
                    )
                    continue
                if method == "ping":
                    ok(id_, {})
                    continue
                if method == "tools/list":
                    ok(id_, {"tools": TOOLS})
                    continue
                if method == "tools/call":
                    tool_name, args = params.get("name"), params.get("arguments") or {}
                    if not tool_name:
                        err(id_, -32602, "Missing tool name")
                        continue
                    ok(id_, handle_tools_call(tool_name, args))
                    continue
                if id_ is not None:
                    err(id_, -32601, f"Method not found: {method}")
            except Exception as e:
                if msg.get("id") is not None:
                    err(
                        msg["id"],
                        -32000,
                        str(e),
                        data={"trace": traceback.format_exc()},
                    )
                else:
                    _log_limited(
                        "notif_err",
                        "notification error:",
                        traceback.format_exc(),
                        interval_sec=2.0,
                    )
    finally:
        shutdown()


if __name__ == "__main__":
    main()
