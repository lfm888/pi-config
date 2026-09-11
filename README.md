# pi-config

一套可移植的 **pi coding agent** 配置：MCP 服务器、skills、pi 包、Web UI。
在任意主机（含私人主机/服务器）上一条命令复刻。

## 目录结构

```
pi-config/
├── install.sh                      # 一键安装（幂等，可重复执行）
├── .gitignore                      # 密钥/缓存排除清单
├── mcp/
│   └── mcp.json.template           # MCP 服务器配置模板（{{HOME}} 安装时替换）
├── skills/
│   ├── brainstorming/              # 需求/设计协作（写代码前必须过设计关）
│   ├── codex-grade-coding/         # 高级工程师级编码协议
│   └── grill-me/                   # 对计划/方案层层追问
├── pi/
│   ├── settings.json.template      # pi 设置模板（新主机首次创建时用）
│   └── packages.txt                # pi 包列表（install.sh 逐个安装）
├── pi-web-ui/
│   └── pi-web-ui.service.template  # 用户级 systemd 服务模板
└── env/
    └── env.example                 # 环境变量示例（GitHub token 等）
```

## 快速部署（新主机）

```bash
# 1. 克隆
git clone <你的仓库地址> ~/pi-config
cd ~/pi-config

# 2. 一键安装（幂等）
./install.sh

# 3. 设置 GitHub token（追加到 ~/.bashrc 后重开终端）
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxxx"

# 4. 在 pi 里让配置生效
/reload
/mcp          # 检查 4 个 MCP 服务器状态
```

> 安装是幂等的：改完配置后随时随地再跑一次即可，不会重复破坏任何东西。
> 被修改的旧文件会自动备份到 `~/.pi-config-backup/<时间戳>/`。

### install.sh 选项

```bash
./install.sh --dry-run              # 预览将执行的操作
./install.sh --skip-packages        # 跳过 pi 包安装
./install.sh --skip-web-ui          # 跳过 pi-web-ui
./install.sh --keep-legacy-skills   # 保留 ~/.opencode/skills 等旧目录（默认移除防重复）
./install.sh --port 9000            # pi-web-ui 端口
./install.sh --workspace ~/project  # pi-web-ui 工作目录
```

## MCP 服务器

| 服务器 | 包 | 已验证版本 | 工具数 | 说明 |
|--------|-----|-----------|--------|------|
| `filesystem` | `@modelcontextprotocol/server-filesystem` | 2026.8.31 | 14 | 文件读写（限定 `$HOME`）|
| `github` | `@modelcontextprotocol/server-github` | 2025.4.8 | 26 | GitHub API（需要 `GITHUB_PERSONAL_ACCESS_TOKEN`）|
| `git` | `@cyanheads/git-mcp-server` | 2.15.3 | 28 | 本地 git 操作（status/diff/commit/push…）|
| `chrome-devtools` | `chrome-devtools-mcp` | 1.9.0 | 29 | 浏览器自动化/截图/网络/性能 |

> ⚠️ 历史版本演进（重要！）：
> - ~~`@modelcontextprotocol/server-git`~~ **在 npm 上不存在（404）**，改用 `@cyanheads/git-mcp-server`
> - ~~`@modelcontextprotocol/server-puppeteer`~~ 已**被官方弃用**（no longer supported），改用 `chrome-devtools-mcp`
> - `~/.mcp.json` 是**项目级**路径（只在 cwd 匹配时生效），因此统一迁到全局 `~/.config/mcp/mcp.json`

服务器默认**懒启动**（lazy）：只有真正调用工具时才连接，不占上下文。

## skills

| skill | 来源 | 用途 |
|-------|------|------|
| `brainstorming` | 网络 | 任何创造性工作前必须走的设计流程：分类 → 提问 → 方案 → 批准 → 实现 |
| `codex-grade-coding` | 网络 | 任务分级、验证阶梯、防范围蔓延的编码纪律 |
| `grill-me` | 网络 | 对方案/设计连续追问直到达成共识 |

**指向方式**：`~/.pi/agent/settings.json` 的 `skills` 数组直接引用 `~/pi-config/skills`。
仓库即唯一来源 —— 修改 skill 在仓库里改，`git push` 后私人主机 `git pull` 即生效，无需复制。

## pi 包

见 `pi/packages.txt` —— 当前两个：

- `pi-mcp-adapter` — MCP 适配器（代理工具，防止上下文爆炸）
- `pi-web-access` — 网页搜索/URL 抓取/PDF/视频解析工具

## pi-web-ui

浏览器端 Pi 控制台（流式对话、内置终端、文件树、Git 面板、多会话）。
安装为**用户级 systemd 服务**（无需 sudo），开机自启。

```bash
systemctl --user status pi-web-ui     # 状态
systemctl --user restart pi-web-ui    # 重启
systemctl --user stop pi-web-ui       # 停止
journalctl --user -u pi-web-ui -f     # 日志
```

默认监听 `127.0.0.1:8787`（仅本机）。局域网访问需设 `PI_WEB_HOST=0.0.0.0` 并配合防火墙，建议加 `PI_WEB_TOKEN` —— 注意 pi-web-ui **不是沙箱**，不要在公网裸露。

## 🔒 安全：什么绝对不能提交

仓库 `.gitignore` 已排除以下文件，push 前请再自查：

| 文件 | 内容 |
|------|------|
| `~/.pi/agent/auth.json` | 提供商 API 密钥 |
| `~/.pi/agent/provider-keys.json` | 提供商密钥列表 |
| `~/.pi-config.env` / `.env` | 你本地的 GitHub token 等 |
| `~/.pi/agent/sessions/` | 对话历史（含敏感内容）|
| `~/.pi-web/` | Web UI 状态 |

自查命令：

```bash
cd ~/pi-config
grep -rInE '(ghp_|sk-|AIza|-----BEGIN)' --exclude-dir=.git .
git status   # 确认没有意外文件
```

## 日常维护

```bash
# 改 skill / 改 MCP 配置
cd ~/pi-config && vim skills/brainstorming/SKILL.md   # 或编辑 mcp/mcp.json.template
git add -A && git commit -m "..." && git push

# 私人主机同步
cd ~/pi-config && git pull && ./install.sh

# 改完 MCP 配置后
pi 里执行 /reload
```

## 故障排查

| 现象 | 处理 |
|------|------|
| GitHub 服务器无工具 | 检查 `GITHUB_PERSONAL_ACCESS_TOKEN` 已 export（`/mcp setup` 里也能看）|
| chrome-devtools 连不上 | 需要 Chrome/Chromium 可执行；首次运行自动下载，或设 `CHROME_PATH` |
| `/mcp` 里全部 offline | 服务器是懒启动，调用工具时才连接；先 `mcp({ search: ... })` 触达 |
| 终端空白（pi-web-ui）| node-pty 未编译成功，重装：`npm i -g --allow-scripts=node-pty,@google/genai,protobufjs pi-web-ui` |
| MCP 配置不生效 | 执行 `/reload`；确认没有 `~/.mcp.json` 残留遮蔽全局配置 |

## 已验证环境

- **系统**：Linux (systemd)，用户级服务
- **Node**：v24.18.0（要求 ≥ 22.19）
- **pi**：0.85.1
- **pi-web-ui**：0.76.0
- 所有 MCP 服务器均通过 JSON-RPC 工具探测（initialize + tools/list）