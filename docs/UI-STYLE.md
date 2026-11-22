# 界面样式规范

面向本仓库所有交互式脚本（install.sh、nginx.sh、docker.sh、cert.sh、tools/*）。改动界面输出前先读本文。

## 分隔线

统一用 `─`（U+2500），宽度按终端列数自适应，取值区间 40–80 列：手机终端一行刚好铺满，宽屏不会拉成一条长线。

- 能 `source utils.sh` 的脚本：调 `ui_rule [颜色] [字符]`、`ui_rule_titled <标题> [颜色]`；底层是 `ui_term_cols()`（COLUMNS → stty size，兜底 80、下限 24）与 `ui_rule_width()`（clamp 40–80）。
- 不 `source utils.sh` 的脚本：
  - `install.sh` 内联 `_sep_cols`，用 `printf -v _sep_line '%*s'` 再 `${_sep_line// /─}`。该段在顶层作用域，不能声明 `local`，靠块内各分支 `exec` 收尾避免变量泄漏。
  - `nginx.sh` 用 `_nginx_rule_width()` + `generate_line`。
  - `docker.sh`、`cert.sh` 的 fallback 块各自带一份简化 `ui_rule` / `ui_rule_titled`，供 utils.sh 不可用时兜底。
- 禁止硬编码重复次数（`printf '─%.0s' {1..60}` 之类），长度由终端决定。
- heredoc 里的静态分隔线无法自适应，固定 40 列（见 `MCP/pty/mcp_pty.sh`）。

两个边界：

- `ui_rule_titled` 的标题超过「宽度 − 4」时退化为纯分隔线，不折行。
- `generate_line` 会转义自定义字符里的 `&`：bash 5.2 起 `patsub_replacement` 默认开启，不转义会把 `&` 当成「匹配到的空格」替换回空格。

以下不属于本规范，保持原样：

- `─── 标题 ───` 形式的小节标题线。
- ASCII 框线（`╭─╮`、`+--+`）与对齐用的 `generate_line` 表格线。
- 进度条、表格列宽计算。

## 菜单文案

- 默认文案集中在 `utils.sh` 的 `menu_vocab_phrase()`，全部中文；`config.json` 的 `menus.<MENU>.ui` 可逐项覆盖。
- 新增菜单或分组时，同时补 `menu_schema_default()` 的分支，否则未配置环境拿不到默认词。
- 状态列渲染成 `[值]` 形式，标记类（当前/已启用）由 `menu_ui_status_marker` 决定。
- 二级菜单与主菜单一致，渲染 subtitle / 焦点 / 提示（`ui_append_schema_panel_header`）；`classic` 主题保持紧凑列表，不加 header。
- `menu_schema_default … focus_source` 返回与 `config.json` 同域的英文 key（如 `current_theme`），显示文案由 `menu_resolved_focus_value` 翻译；不要在这里直接返回中文。

## 测试约定

- 路径推导：在 `setup()` 里 `export REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"`。不要用 `BASH_SOURCE[0]`——bats 会把测试文件编译到临时目录，推出来是 `/tmp`。
- 断言取自当前实现的实际输出。重构改了文案就同步改断言，不要保留英文旧值。
- 只 source 部分库文件的用例，要把缺失函数显式 stub 掉（如 `_nginx_config_health_status`、`log_message`），否则 `set -e` 会在无关位置中断。
- 需要计数或跨子 shell 传值时写入临时文件，`$(...)` 里的变量自增不会回传父 shell。

## 改动后自检

```bash
bash -n utils.sh nginx.sh docker.sh cert.sh install.sh
bats tests/ui_meta_snapshot.bats tests/install_secondary_menu_theme.bats
bats tests/nginx_theme_menu.bats tests/nginx_menu_exit.bats
```
