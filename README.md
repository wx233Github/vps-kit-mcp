# vps-kit-mcp VPS 一键安装与运维脚本

一个以 Debian/Ubuntu 为主、部分模块兼容更多发行版的 VPS 自动化脚本集合，提供 Docker、Nginx、证书、Watchtower、TCP 优化等常用运维能力。

---

## 功能概览

- `install.sh`：主入口脚本（菜单调度、更新检查、模块执行）
- `docker.sh`：Docker / Docker Compose 安装与管理
- `nginx.sh`：Nginx 反代、证书、TCP 代理、备份恢复（HTTP 反代支持本机端口、Docker 容器与异机 `host:port` / `http(s)://host:port`，并支持为特殊上游覆盖 Host 请求头，例如 Playwright MCP）
- `cert.sh`：acme.sh 证书申请与管理
- `tools/Watchtower.sh`：容器自动更新（Watchtower）管理
- `tools/bbr_ace.sh`：BBR ACE 网络调优
- `rm/install.sh`：卸载入口
- `rm/rm_cert.sh`：证书相关清理

---

## 快速开始

### 1) 直接运行（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wx233Github/vps-kit-mcp/main/install.sh)
```

### 2) 强制拉取最新脚本（调试/修复场景）

```bash
curl -fsSL "https://raw.githubusercontent.com/wx233Github/vps-kit-mcp/main/install.sh?_=$(date +%s)" | FORCE_REFRESH=true bash -s
```

### 3) 执行并落盘日志到当前目录

```bash
curl -fsSL "https://raw.githubusercontent.com/wx233Github/vps-kit-mcp/main/install.sh?_=$(date +%s)" | FORCE_REFRESH=true bash -s 2>&1 | tee "jb_$(date +%Y%m%d_%H%M%S).log"
```

如果在仓库根目录执行这条命令，会生成 `jb_*.log` 运行日志；该类文件已加入忽略规则，避免污染工作区。

---

## 交互说明（重要）

- 在**子模块主菜单**中直接按回车（Enter），会退出当前脚本链路（不再返回父菜单）。
- 菜单内的具体操作页通常仍可按提示返回上一级菜单。
- 各模块支持**独立运行**，在非 root 场景下会自动尝试 sudo 提权。
- `nginx.sh` 交互模式下配置 HTTP 反代时，后端目标支持三类输入：本机端口（如 `8080`）、Docker 容器名（如 `my-app`）、异机地址（如 `10.0.0.8:8080` 或 `https://svc.internal:8443`）。

### 终端 UI 主题与文案自定义

- 默认主题位于 `/opt/vps_install_modules/config.json` 的 `ui.theme`，当前支持：`retro-launcher`、`classic`、`compact`、`minimal`。
- 主菜单与二级菜单都支持通过 `config.json` 的 `menus.<MENU>.ui` 覆盖文案；未填写的字段会回退到内置的 schema/default registry（定义在 `utils.sh`）。
- 常用覆盖字段：
  - `subtitle`：页头副标题
  - `repo`：仅 `MAIN_MENU` 使用的仓库/来源行
  - `hint`：页脚上方的提示语
  - `meta_labels.version/theme/update`：首页 meta label 文案
  - `status_labels.<action>`：状态摘要标签，例如 `docker.sh`、`THEME_MENU`、`toggle_startup_update_mode`
  - `status_markers.current`：主题菜单里当前主题的标记文案
  - `groups.<group>`：分区标题，例如 `core`、`tools`、`profiles`
  - `sections.<section>`：页面分区标题，例如模块页里的 `runtime_overview`、`action_center`、`operations_policy`
  - `focus.key/value/source`：二级菜单的 Focus 行；当 `source` 为 `current_theme` 时，会自动显示当前主题名称
- 模块页（如 `DOCKER_MENU`、`DOCKER_INSTALL_MENU`、`DOCKER_BOOTSTRAP_MENU`、`CERT_MENU`、`CERT_MAINTENANCE_MENU`、`WATCHTOWER_MENU`、`BBR_MENU`、`BBR_KERNEL_MENU`、`NGINX_MENU`）的 header 与 section 默认文案也来自 `utils.sh` 的共享 registry；新增菜单页时，优先补 `menu_schema_default()` / `menu_ui_*`，不要在模块里再塞一套硬编码默认词表。
- 这些逻辑菜单 ID 不需要先出现在仓库自带的 `config.json` 里；只要你在本机 `/opt/vps_install_modules/config.json` 的 `menus.<MENU>.ui` 下新增对应节点，就会覆盖共享默认值。
- 逻辑菜单 ID 一览：

| 菜单 ID | 典型页面 | 可覆盖内容 |
| --- | --- | --- |
| `DOCKER_MENU` | Docker 已安装主菜单 | `subtitle` / `hint` / `focus.*` / `sections.*` |
| `DOCKER_INSTALL_MENU` | Docker 安装管理页 | `subtitle` / `hint` / `focus.*` / `sections.recovery_lifecycle` |
| `DOCKER_BOOTSTRAP_MENU` | Docker 未安装引导页 | `subtitle` / `hint` / `focus.*` / `sections.bootstrap_overview` / `sections.launch_pad` |
| `CERT_MENU` | 证书主菜单 | `subtitle` / `hint` / `focus.*` / `sections.*` |
| `CERT_MAINTENANCE_MENU` | 证书系统维护页 | `subtitle` / `hint` / `focus.*` / `sections.diagnostics` / `sections.policy_control` |
| `WATCHTOWER_MENU` | Watchtower 主菜单 | `subtitle` / `hint` / `focus.*` / `sections.service_overview` / `sections.action_center` |
| `BBR_MENU` | BBR ACE 主菜单 | `subtitle` / `hint` / `focus.*` / `sections.*` |
| `BBR_KERNEL_MENU` | BBR 内核维护页 | `subtitle` / `hint` / `focus.*` / `sections.recovery_lifecycle` |
| `NGINX_MENU` | Nginx 主菜单 | `subtitle` / `hint` / `focus.*` / `sections.http_workloads` / `sections.transport_routing` / `sections.operations_policy` |
- 配置示例：

```json
{
  "ui": {
    "theme": "retro-launcher"
  },
  "menus": {
    "MAIN_MENU": {
      "ui": {
        "subtitle": "Custom main subtitle",
        "repo": "Repo: example/custom",
        "meta_labels": {
          "version": "Build",
          "theme": "Skin",
          "update": "Refresh"
        },
        "groups": {
          "core": "Core Lane",
          "tools": "Utility Deck",
          "system": "Control Room"
        },
        "status_labels": {
          "docker.sh": "Engine",
          "THEME_MENU": "Profile"
        }
      }
    },
    "THEME_MENU": {
      "ui": {
        "status_markers": {
          "current": "Selected"
        },
        "focus": {
          "source": "current_theme"
        }
      }
    },
    "DOCKER_MENU": {
      "ui": {
        "sections": {
          "runtime_overview": "Runtime Deck",
          "action_center": "Control Actions",
          "recovery_lifecycle": "Recovery Lane"
        }
      }
    },
    "DOCKER_INSTALL_MENU": {
      "ui": {
        "hint": "Choose how to rebuild or retire the current Docker runtime.",
        "sections": {
          "recovery_lifecycle": "Lifecycle Controls"
        }
      }
    },
    "BBR_KERNEL_MENU": {
      "ui": {
        "focus": {
          "value": "Kernel Lane"
        },
        "sections": {
          "recovery_lifecycle": "Kernel Recovery"
        }
      }
    }
  }
}
```

### 清屏策略

- 当前默认与运行时策略均为 `off`（关闭自动清屏）

---

## 常见维护命令

### Nginx 模板中心 CLI（非交互）

- 预检查（不写入）：
  - `--template-precheck`
- 影响分析（不写入）：
  - `--template-impact-report`
  - `--json` 时包含域名级“模板块/指令变化”摘要
- 按操作ID回滚：
  - `--template-rollback-op <op_id>`
- 审计统计：
  - `--template-audit-report`（可配合 `--json`）
- 批量匹配（glob + 排除）：
  - `--template-domain "*.example.com,!admin.example.com"`
- 模板变量注入（受 manifest 白名单约束）：
  - `--template-vars HSTS_MAX_AGE=86400`
  - 例如：`PROXY_CONNECT_TIMEOUT=120s,WP_CLIENT_MAX_BODY_SIZE=128m`
- 批量失败策略：
  - `--fail-fast`（遇错即停）
  - `--continue-on-error`（遇错继续）
- 批量并行（仅 dry-run/precheck/impact）：
  - `--template-parallelism 4`
- 输出模式：
  - `--json`（机器可读摘要）
  - `--quiet`（减少控制台输出）
- 审批门禁：
  - `--template-approval-hook /abs/path/to/hook`
- 精准回滚：
  - `--template-rollback-domain <domain>`
  - `--template-rollback-before "YYYY-MM-DD HH:MM:SS"`

示例：

`bash nginx.sh --template-mode custom --template-domain "*.example.com,!admin.example.com" --template-ids security_headers --template-precheck --json --non-interactive`

`bash nginx.sh --template-rollback-op <op_id> --json --non-interactive`

### 调试主脚本

```bash
sudo bash -x /opt/vps_install_modules/install.sh
```

### install.sh Headless CLI

- 仅查看当前运行状态与环境摘要：
  - `bash install.sh status`
  - `bash install.sh status --json`
- 执行环境自检（不修改系统）：
  - `bash install.sh doctor`
  - `bash install.sh doctor --json`
- 强制全面更新所有模块和配置：
  - `bash install.sh update`
- 直接走安装脚本内置卸载入口：
  - `bash install.sh uninstall`
  - `bash install.sh --uninstall`
  - `bash install.sh -u`

其中 `--json` 仅与 `status` / `doctor` 搭配使用。

### Watchtower CLI（非交互）

- 诊断当前配置、最近一次运行快照与容器状态：
  - `bash tools/Watchtower.sh --diagnose`
- 导出当前 Watchtower 配置：
  - `bash tools/Watchtower.sh --export-config`
- 导入配置文件（会先校验再覆盖当前配置）：
  - `bash tools/Watchtower.sh --import-config /abs/path/to/file`

`tools/watchtower.env` 与 `tools/watchtower.env.last_run` 为运行期生成文件，不纳入版本控制。
`--diagnose` 额外提供 `env_file_last_run_consistency`，用于判断最近一次成功生成的运行快照与当前配置是否一致。

### cert.sh CLI（非交互）

- 证书体检（检查 acme.sh 安装状态与近 30 天到期证书）：
  - `bash cert.sh --health-check`
- 仅记录破坏性操作，不实际执行：
  - `bash cert.sh --dry-run`

### docker.sh CLI（补充）

- 仅记录破坏性操作，不实际执行：
  - `bash docker.sh --dry-run`

`cert.sh --dry-run` 与 `docker.sh --dry-run` 为 dry-run 模式开关：会进入原有流程，但不会真正执行破坏性操作。

### 重置安装目录与命令链接

```bash
sudo sh -c "rm -rf /opt/vps_install_modules && rm -f /usr/local/bin/cc"
```

### 仅重置配置文件

```bash
sudo rm -f /opt/vps_install_modules/config.json
```

---

## 卸载入口

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wx233Github/vps-kit-mcp/main/rm/install.sh)
```

---

## 兼容性与权限

- 系统：Debian / Ubuntu（其他发行版请自行评估）
- 权限：涉及系统配置变更时需要 root 或可用 sudo
- 提权兼容：若以 `bash <(curl ...)` 方式运行且需要提权，脚本会自动落盘临时副本后再 sudo 重启执行

---

## 免责声明

本仓库脚本会修改系统服务与配置（如 Nginx、Docker、证书、内核网络参数）。
请在生产环境使用前先在测试机验证，并做好快照/备份。
