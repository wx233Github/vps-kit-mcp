# PTY-runner usage policy (opencode MCP)

The `pty-runner` MCP server is provided by the PyPI package `pty-mcp`. By default, the integration resolves `pty-mcp` via `uvx --from pty-mcp pty-mcp`; deployments may pin a specific spec when needed.

When a task requires interactive terminal UI or TTY-only behavior, use the MCP server `pty-runner` rather than guessing outputs.

## When to use pty-runner
Use `pty-runner` for any of the following:
- Interactive CLI menus / prompts (e.g. "choice", "请输入选项", "Press Enter", yes/no prompts)
- Programs that require a TTY (full-screen UI, curses, installers, scripts that behave differently without a terminal)
- Anything that depends on real TTY behavior or full-fidelity terminal output

For non-interactive, simple inspection commands (e.g. path checks, listing files, showing configs), you may use the standard bash tool as long as you still show real command output and avoid guessing.

When using a PTY session, always verify the runtime environment first (e.g. `pwd`, `ls`) because PTY sessions may start in a different working directory.

## Common tool workflow

- Basic lifecycle: `pty_spawn` → `pty_read` / `pty_read_until` → `pty_write` → `pty_close`
- Wait helpers: `pty_read_until_any`, `pty_read_quiescent`, `pty_prompt`
- Session inspection: `pty_status`, `pty_wait`, `pty_list`
- Stream-specific reads: `pty_read_stdout` / `pty_read_stderr` (requires `separate_streams=true` in `pty_spawn`; once enabled, stdout/stderr no longer flow through the main PTY buffer in the same way)
- Optional control/admin tools: `pty_signal`, `set_default_cwd`, `get_default_cwd`, `set_limits`, `get_limits`, `pty_metrics`, `pty_health` (only when enabled by runtime policy)
- High-risk commands: `confirm_dangerous_command` is the default path for dangerous commands; pass the returned `dangerous_confirm_token` into `pty_spawn`

## How to use (required workflow)
1. Start a session with `pty_spawn`.
   - Under the default policy, provide a stable `owner` value and reuse that same `owner` for later session-bound calls.
2. Read output with `pty_read`, `pty_read_until`, or `pty_read_until_any`.
3. Only send inputs using `pty_write` (include `\n` for Enter).
4. Continue reading and present the output verbatim to the user.
5. Close the session with `pty_close` when done.

## Output handling rules
- Do NOT fabricate terminal output. Only quote what was returned by `pty_read`.
- If output is incomplete, keep calling `pty_read` with a short `timeout_ms` (e.g. 300–800ms) until stable.
- If you need deterministic waiting, prefer `pty_read_until`, `pty_read_until_any`, or `pty_read_quiescent` over arbitrary sleeps.
- If you need stdout/stderr separation, set `separate_streams=true` at spawn time before calling `pty_read_stdout` / `pty_read_stderr`; after that, do not assume the main `pty_read` buffer still contains the same stdout/stderr stream content.

## Sudo rules
- Never ask for or type a sudo password.
- Prefer `sudo -n <command>` so it fails fast if passwordless sudo is not configured.
- If sudo prompts for a password or fails, stop and ask the user to handle sudo configuration.

## Safety/confirmation
- If a step could change system state (install/remove packages, modify configs), ask the user for confirmation before proceeding to the next irreversible action.
- For obviously dangerous commands (e.g. destructive file deletion, reboot, shutdown, disk operations), use `confirm_dangerous_command` first, then pass the returned `dangerous_confirm_token` into `pty_spawn`.
- Legacy dangerous-command confirmation via `dangerous_confirmed` / `dangerous_justification` is compatibility-only and requires `PTY_MCP_DANGEROUS_LEGACY_MODE=1`.
