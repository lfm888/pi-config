# pi-config

一套可移植的 **pi coding agent** 配置：MCP 服务器、skills、pi 包、Web UI。
在任意主机（含私人主机/服务器）上一条命令复刻。

## 目录结构

```
pi-config/
├── install.sh                      # 一键安装（幂等，可重复执行）
├── sync.sh                         # 一键同步：git pull + install.sh
├── verify.sh                       # push 前自检：探测 MCP / 校验 skills / 扫密钥
├── add-mcp.sh                      # 添加新 MCP 服务器（可选探测验证）
├── add-skill.sh                    # 添加新 skill（本地目录或 GitHub）
├── scripts/
│   └── mcp-probe.mjs               # JSON-RPC 探测脚本（共享）
├── shell/
│   └── pi-open-web.sh              # 「输入 pi 自动打开 Web UI」shell 钩子
├── .gitignore                      # 密钥/缓存排除清单
├── mcp/
│   └── mcp.json.template           # MCP 服务器配置模板（{{HOME}} 安装时替换）
├── skills/                         # 全部 skill（pi 的 settings.json 直接指向这里）
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

服务器采用 **eager 启动**：每次会话启动即连接全部 4 个服务器（`/mcp` 立即可见连接状态）。
想省资源时，把任意服务器的 `"lifecycle": "eager"` 改成 `"lazy"` 即可（默认懒启动）。

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

**输入 `pi` 自动打开 Web UI**：安装器会把 `shell/pi-open-web.sh` 追加到你的 shell 配置，行为：

| 输入 | 行为 |
|------|------|
| `pi`（不带参数）| 确保服务在运行 → 自动打开浏览器 `http://127.0.0.1:8787` |
| `pi "提问"` / `pi --print ...` | 仍走终端 TUI（原功能保留）|
| `pi-tui` 或 `\pi` | 强制进入终端 TUI |
| 无图形环境（SSH）| 不弹浏览器，只打印访问地址 |

想取消该行为：从 `~/.bashrc`（或 `~/.zshrc`）删除 `pi-config: pi → 打开 Web UI` 标记块。

**GitHub token 生效路径**（两个入口各自独立）：

| 入口 | token 来源 | 生效方式 |
|------|-----------|---------|
| 终端 `pi` / TUI | `~/.bashrc` 的 `export GITHUB_PERSONAL_ACCESS_TOKEN=...` | 新开终端（或 `source ~/.bashrc`）|
| pi-web-ui 服务（网页） | `~/.config/pi-web.env`（install.sh 自动生成，600 权限，可从 ~/.bashrc 迁移）| `systemctl --user restart pi-web-ui`（会中断当前网页会话）|

> systemd 服务**不读** `~/.bashrc`，所以 web 会话的 token 必须放在 `~/.config/pi-web.env`（`EnvironmentFile` 引用，该文件在仓库外、不提交）。

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

## 维护工作流（看到好东西 → 加进来 → 全机器生效）

### 添加 MCP 服务器

```bash
# npm 包服务器（自动以 npx 启动；--test 先探测验证；--apply 本机立即生效）
./add-mcp.sh --name memory --package @modelcontextprotocol/server-memory \
             --args '{{HOME}}/memory.json' --test --apply

# 远程 HTTP 服务器
./add-mcp.sh --name docs --url https://mcp.example.com/mcp --test

# 完整自定义条目
./add-mcp.sh --name foo --entry '{"command":"npx","args":["-y","some-server"]}'
```

要点：
- `--args` 里用 `{{HOME}}` 等占位符，安装时按各机器目录替换（可移植）
- `--env` 里的 `${VAR}` 原样保留，由 pi-mcp-adapter 在运行时展开（如 GitHub token）
- 强烈建议加 `--test`：写入前先做 JSON-RPC 探测，包不存在/启动失败会当场中止
- 同名配置会拒绝，加 `--force` 才覆盖

### 添加 skill

```bash
# 从 GitHub（整个仓库 / 子目录 / 指定分支；--commit 自动提交）
./add-skill.sh --source github.com/owner/some-skill --ref main --commit
./add-skill.sh --source github.com/owner/big-repo/sub/dir

# 从本地目录
./add-skill.sh --source ~/下载/my-skill --name my-skill
```

要点：
- 强制要求 SKILL.md 且 frontmatter 含 `name` + `description`（name 须与目录名一致）
- 校验失败自动回滚，不留下半成品
- 添加即生效 —— pi 的 settings.json 已指向 `skills/` 目录，无需任何额外注册
- 克隆走 git(HTTP/1.1) + codeload tarball 双重兜底，GitHub 网络不稳也能用

### push 前自检

```bash
./verify.sh              # 完整：探测全部 MCP 服务器 + 校验 skills + 扫密钥
./verify.sh --no-probe   # 只做静态检查（离线可用，快）
```

### 任何机器一键同步

```bash
./sync.sh                # git pull + ./install.sh（幂等）
```

### 标准流程（本机发现 → 全球生效）

```bash
cd ~/pi-config
./add-mcp.sh --name xxx --package yyy --test    # 或 ./add-skill.sh ...
./verify.sh                                      # push 前自检
git add -A && git commit -m "add xxx" && git push
# 其他机器：
./sync.sh                                        # 拉取 + 应用
pi 里执行 /reload                                # 让 MCP 生效
```

> MCP 配置变更后需要在 pi 里执行 `/reload`；skills 变更无需任何操作。

## 故障排查

| 现象 | 处理 |
|------|------|
| github 服务器连接报错 | `GITHUB_PERSONAL_ACCESS_TOKEN` 未设置；eager 模式下启动即报错，设置后 `/reload` |
| GitHub 服务器无工具 | 检查环境变量已 export（`echo $GITHUB_PERSONAL_ACCESS_TOKEN`）|
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

---

## Windows 专用部署

> 本章节针对 Windows (Git Bash / PowerShell) 环境的部署细节。

### 前置条件

- **Node.js** ≥ v22.19 (官方安装或 NVM)
- **Git for Windows** (建议安装至 `D:\lfm\Git`，`bin\bash.exe` 可用)
- **Visual Studio Build Tools** (x86-64，必须选组件："使用 C++ 的桌面开发"，node-pty 编译必需)
- **Python** (≥ v3.8，建议从 python.org 安装并添加至 PATH)

### 一键安装 (推荐)

打开 **Git Bash** (D:\lfm\Git\bin\bash.exe) 并执行：

```bash
# 1. 克隆仓库到主目录
git clone <仓库地址> ~/pi-config
cd ~/pi-config

# 2. 配置 GitHub Token (仅需一次，写入 ~/.bashrc)
export GITHUB_PERSONAL_ACCESS_TOKEN=""
echo 'export GITHUB_PERSONAL_ACCESS_TOKEN=""' >> ~/.bashrc

# 3. 运行安装脚本 (幂等，可重复执行)
./install.sh

# 4. 启动 pi-web-ui (Windows 无 systemd，需手动启动)
pi-web-ui
# 浏览器自动打开: http://127.0.0.1:8787
# 如不自动打开，手动访问 http://localhost:8787
```

### 常用命令备忘

| 操作 | Git Bash 命令 | 说明 |
|------|--------------|------|
| 启动 pi-web-ui | `pi-web-ui` | 默认 `http://127.0.0.1:8787` |
| 重载 MCP 配置 | `/reload` | 在 pi 终端执行 |
| 检查 MCP 状态 | `/mcp` | 在 pi 终端执行 |
| 同步更新 | `./sync.sh` | `git pull + ./install.sh` |
| 技能变更生效 | 无需操作 | `git pull` 后自动生效 |
| 关闭 pi-web-ui | `Ctrl+C` | 或关闭终端窗口 |

### 已知限制

- **node-pty 编译**：Windows 上需 Visual Studio Build Tools，若编译失败，pi-web-ui 的内置终端可能不可用（核心聊天功能正常）
- **systemd 服务**：Windows 无法使用 `systemctl --user` (除非 WSL2 + systemd)，所有服务需手动启动
- **GitHub token**：写入 `~/.bashrc` 后每个新终端自动生效；pi-web-ui 服务单独读取 `~/.config/pi-web.env`

### 后续同步

```bash
cd ~/pi-config
./sync.sh  # git pull + ./install.sh (幂等)
```