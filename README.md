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
│   ├── mcp-probe.mjs               # JSON-RPC 探测脚本（共享）
│   └── render-template.mjs         # 模板渲染器（install.sh / verify.sh 共用）
├── shell/
│   └── pi-web-ui.bat               # Windows 启动包装（可选，等价于直接跑 pi-web-ui）
├── .gitattributes                  # 换行符统一（文本 LF、Windows 脚本 CRLF）
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
./install.sh --windows-service      # Windows：代为安装 pi-web-ui 自启服务（HKCU Run 键）
./install.sh --keep-legacy-skills   # 保留 ~/.opencode/skills 等旧目录（默认移除防重复）
./install.sh --mcp-mode merge       # MCP 写入策略：merge(默认)/keep-local/reset
./install.sh --port 9000            # pi-web-ui 端口
./install.sh --workspace ~/project  # pi-web-ui 工作目录
```

`--mcp-mode` 决定 `~/.config/mcp/mcp.json` 的写入方式（**默认绝不静默丢弃本机配置**）：

| 模式 | 行为 |
|------|------|
| `merge`（默认）| 模板里定义过的服务器以模板为准；本机额外添加的服务器保留；每处差异都会打印出来 |
| `keep-local` | 只补齐本机还没有的服务器；已存在的条目一律不动（保护本机热修，比如版本钉定）|
| `reset` | 完全以模板覆盖（旧行为，会移除本机独有服务器）|

## MCP 服务器

| 服务器 | 包 | 已验证版本 | 工具数 | 说明 |
|--------|-----|-----------|--------|------|
| `filesystem` | `@modelcontextprotocol/server-filesystem`（**本地自包含安装**，见下）| 2026.8.31 + zod 4.6.5 | 14 | 文件读写（限定 `$HOME`）|
| `github` | `@modelcontextprotocol/server-github` | 2025.4.8 | 26 | GitHub API（需要 `GITHUB_PERSONAL_ACCESS_TOKEN`）|
| `git` | `@cyanheads/git-mcp-server` | 2.15.3 | 28 | 本地 git 操作（status/diff/commit/push…）|
| `chrome-devtools` | `chrome-devtools-mcp` | 1.9.0 | 29 | 浏览器自动化/截图/网络/性能（`lazy` 启动；自动探测本机浏览器）|

> ⚠️ 历史版本演进（重要！）：
> - ~~`@modelcontextprotocol/server-git`~~ **在 npm 上不存在（404）**，改用 `@cyanheads/git-mcp-server`
> - ~~`@modelcontextprotocol/server-puppeteer`~~ 已**被官方弃用**（no longer supported），改用 `chrome-devtools-mcp`
> - ⚠️ `@modelcontextprotocol/server-filesystem` 有两个坑（都实测踩过）：
>   1. **npx 装 2026.x 时顶层缺 `zod`**（zod 只被嵌套装进 sdk 的 `node_modules`）→ 启动即 `ERR_MODULE_NOT_FOUND`
>   2. **光钉服务器版本也不够**：npm 会把传递依赖 `zod` 解析成 **4.x**，而该服务器的 schema 生成器 `zod-to-json-schema@3` 在 zod 4 下产出**缺 `type` 的非法 JSON Schema** → 客户端报 `Invalid result for tools/list: ... inputSchema.type`
>
>   因此 filesystem **不用 npx**：由 `install.sh` 在 `~/.pi/mcp-servers` 做本地自包含安装（显式钉 `zod@4.6.5`），配置里用 `node <bin>` 直跑。详见下节。
> - 其余 MCP 条目仍建议钉版本（如 `chrome-devtools-mcp@1`），避免被上游 `latest` 变更打穿。
> - `~/.mcp.json` 是**项目级**路径（只在 cwd 匹配时生效），因此统一迁到全局 `~/.config/mcp/mcp.json`

服务器启动策略（`lifecycle`）：`filesystem` / `github` / `git` 用 **eager**（会话启动即连，`/mcp` 立即可见状态）；
`chrome-devtools` 用 **lazy** —— 它会拉起 Chrome，没必要每次开会话都启动，首次调用其工具时才连接。
可选值：`eager` / `lazy` / `keep-alive` / `lazy-keep-alive`。

**浏览器可执行路径**：`chrome-devtools-mcp` 默认只认系统 Chrome（Linux 上是 `/opt/google/chrome/chrome`），
识别不了 Chromium（含 snap 安装）、Brave、Edge 等。`install.sh` 会自动探测本机浏览器，并把路径以
`--executablePath=...` 的形式写进 `~/.config/mcp/mcp.json` —— 这属于「本机增强」，仓库模板保持干净可移植。
探测顺序：`PATH` 里的 `google-chrome` / `chromium` / `chromium-browser` / `brave-browser` / `microsoft-edge`，
然后是 `/opt/google/chrome/chrome`、`/snap/bin/chromium`、macOS 的 `Google Chrome.app` 等固定路径。
装好浏览器后重跑 `./install.sh` 即可自动补上（已指向有效路径时不会改动）。

### filesystem 为什么不用 npx（以及怎么升级）

npx 只能指定**一个**包名，管不住传递依赖：服务器自己声明的是 `zod-to-json-schema@3`，但该包的 peer 范围是
`^3.25.28 || ^4`，npm 于是把 `zod` 装成了 **4.x**，两者组合会生成缺 `type: "object"` 的 schema，客户端直接拒收。

所以 filesystem 改成“本地自包含安装 + node 直跑”：

- 安装目录：`~/.pi/mcp-servers`（仓库外，由 `install.sh` 幂等维护；版本不符会自动重装）
- 实际命令：`node ~/.pi/mcp-servers/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js <允许目录>`
- 升级：改 `install.sh` 顶部的 `MCP_FILESYSTEM_PKGS`（空格分隔的 `包@版本`），重跑 `./install.sh`，再用 `./verify.sh --only filesystem` 验证
- 另 3 个服务器继续走 npx：`server-github` 自己声明了 `zod@^3`，不踩这个坑

### 可选：GitHub 换官方远程 MCP（OAuth，免 PAT）

`github` 目前用 npm 上已归档的 `@modelcontextprotocol/server-github` + `GITHUB_PERSONAL_ACCESS_TOKEN`。
想免掉 token 管理，可换成 GitHub 官方远程服务器（pi-mcp-adapter 内置预设，走 OAuth）：

```json
"github": { "url": "https://api.githubcopilot.com/mcp", "auth": "oauth", "protocolVersion": "auto" }
```

改完在 pi 里执行 `/mcp` 按提示完成一次浏览器授权。注意：首次需要交互、依赖 GitHub Copilot 账号权限、离线不可用 —— 所以默认仍保留 PAT 方案。

## skills

| skill | 来源 | 用途 |
|-------|------|------|
| `brainstorming` | 网络 | 任何创造性工作前必须走的设计流程：分类 → 提问 → 方案 → 批准 → 实现 |
| `codex-grade-coding` | 网络 | 任务分级、验证阶梯、防范围蔓延的编码纪律 |
| `grill-me` | 网络 | 对方案/设计连续追问直到达成共识 |

**指向方式**：`~/.pi/agent/settings.json` 的 `skills` 数组直接引用 `~/pi-config/skills`。
仓库即唯一来源 —— 修改 skill 在仓库里改，`git push` 后私人主机 `git pull` 即生效，无需复制。

## pi 包

见 `pi/packages.txt` —— **这是包列表的唯一真源**（`install.sh` 读它来 `pi install`，并同步写进 `~/.pi/agent/settings.json`），当前两个：

- `pi-mcp-adapter` — MCP 适配器（代理工具，防止上下文爆炸）
- `pi-web-access` — 网页搜索/URL 抓取/PDF/视频解析工具

## pi-web-ui

浏览器端 Pi 控制台（流式对话、内置终端、文件树、Git 面板、多会话）。
安装为**用户级 systemd 服务**（无需 sudo），开机自启。

**命令约定**（本仓库**不覆盖** `pi`，各走各的）：

| 输入 | 行为 |
|------|------|
| `pi` | 终端 TUI（pi 原生行为，不做任何重定向）|
| `pi-web-ui` | 启动/连接 Web UI，并自动打开浏览器 `http://127.0.0.1:8787` |
| `pi-web-ui server install` / `server shortcut` | 装成开机自启服务 / 生成桌面图标 |

> 历史版本会往 shell 配置追加一段「输入 `pi` 自动打开 Web UI」的钩子（把 `pi` 覆盖成打开浏览器）。
> 现在不再使用，`install.sh` 会**自动清理**该标记块（幂等）：手动清理即删除 `~/.bashrc`
> （或 `~/.zshrc`）里 `pi-config: pi → 打开 Web UI` 到 `pi-config: end` 之间的内容。

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

### 模板渲染规则（`{{VAR}}`）

模板（如 `mcp/mcp.json.template`）由 `scripts/render-template.mjs` 渲染，install.sh 与 verify.sh 共用同一实现：

| 规则 | 说明 |
|------|------|
| `{{VAR}}` | 替换为同名环境变量；**变量名只能是 `[A-Z0-9_]`** |
| `{{VAR\|\|默认值}}` | ❌ **不支持**，渲染会直接失败退出（曾有人为了绕开 Windows 反斜杠问题改成这种写法，正确解法见下一条）|
| `${VAR}` | 原样保留，由 pi-mcp-adapter 在启动服务器时展开（如 GitHub token）|
| JSON 模板（`--json`）| 注入值做 **JSON 转义**（Windows 的 `C:\...` 反斜杠会被正确转义），并把 Git Bash 的 MSYS 路径 `/c/x` 转成 `C:/x`（Node/pi 不认 `/c/...`）|

> 不转义会写出非法 JSON，不转换会写出 Node 找不到的路径 —— 两者都真实发生过，现在由 `verify.sh` 的“模板渲染校验”拦下。

### push 前自检

```bash
./verify.sh              # 完整：渲染校验 + 探测全部 MCP 服务器 + 校验 skills + 扫密钥
./verify.sh --no-probe   # 只做静态检查（离线可用，快）
./verify.sh --only filesystem   # 只探测指定服务器（4 个全探较慢，改一个条目时用）
```

`--no-probe` 的静态检查覆盖：

1. **模板渲染**：用 `scripts/render-template.mjs` 渲染 `mcp/mcp.json.template`（与 install.sh 同一实现）
2. **残留占位符**：渲染后仍有 `{{...}}` → 直接失败（写法不受支持）
3. **JSON 合法性**：渲染结果必须能被 `JSON.parse`（Windows 路径反斜杠不转义就会在这里被抓住）
4. **本机 skills 路径**：`~/.pi/agent/settings.json` 里的 skills 路径必须真实存在 —— 仓库被移动/删除时 pi 是**静默失效**的（不报错，只是少加载 skills）
5. skills frontmatter 校验 + 密钥扫描

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
| chrome-devtools 报 "Could not find Google Chrome executable" | 本机没装 Chrome，或只装了 Chromium/Edge。重跑 `./install.sh` 会自动探测并写入 `--executablePath`；也可手动在 `~/.config/mcp/mcp.json` 的 `chrome-devtools.args` 里加 `--executablePath=/你的/浏览器/路径`，然后 `/reload` |
| `/mcp` 里全部 offline | 服务器是懒启动，调用工具时才连接；先 `mcp({ search: ... })` 触达 |
| 终端空白（pi-web-ui）| node-pty 未编译成功，重装：`npm i -g --allow-scripts=node-pty,@google/genai,protobufjs pi-web-ui` |
| MCP 配置不生效 | 执行 `/reload`；确认没有 `~/.mcp.json` 残留遮蔽全局配置 |
| `filesystem` 报 `ERR_MODULE_NOT_FOUND` | 拉到了有缺陷的 2026.x npx 安装（顶层无 zod）；确认 `~/.config/mcp/mcp.json` 里是 `node <~/.pi/mcp-servers/...>` 直跑，改完 `/reload` |
| Windows 上 `verify.sh` 报 `spawn npx ENOENT` | 老版 `mcp-probe.mjs` 直接 `spawn("npx")`，而 Windows 的 npx 是 `.cmd` 包装（不走 shell 就 ENOENT）→ 已修（Windows 下改走 shell）；`git pull` 后重试 |
| `Invalid result for tools/list ... inputSchema.type` | filesystem 的 zod 漂到 4.x（npx 装的典型症状）→ 改用本地自包含安装：重跑 `./install.sh`（会装到 `~/.pi/mcp-servers`）后 `/reload` |
| skills 不生效（无任何报错）| `~/.pi/agent/settings.json` 的 skills 路径悬空（仓库被移动/删除）→ 重跑 `./install.sh`；`./verify.sh --no-probe` 会提前报出来 |
| Windows 上 packages 变成注释文字 | 老版 install.sh 的 CRLF 解析 bug（已修）→ `git pull` 后重跑 `./install.sh` |

## 已验证环境

- **系统**：Linux (systemd) 用户级服务；Windows 11 + Git Bash（`C:\Program Files\Git`）
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

打开 **Git Bash**（默认 `C:\Program Files\Git\bin\bash.exe`）并执行：

```bash
# 1. 克隆仓库到主目录
git clone <仓库地址> ~/pi-config
cd ~/pi-config

# 2. 配置 GitHub Token (仅需一次，写入 ~/.bashrc)
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_你的token"
echo 'export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_你的token"' >> ~/.bashrc

# 3. 运行安装脚本 (幂等，可重复执行)
./install.sh

# 4. 启动 pi-web-ui（Windows 无 systemd）
pi-web-ui                       # 前台运行（Ctrl+C 停止）

# 开机自启 + 隐形启动（推荐）：
pi-web-ui server install --port 8787 --cwd "$USERPROFILE"   # 写 HKCU Run 键，登录自启
pi-web-ui server shortcut                                   # 桌面一键启动图标
# 或直接让 install.sh 代跑：./install.sh --windows-service
# 浏览器没自动打开时，手动访问 http://localhost:8787
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
- **systemd 服务**：Windows 无法使用 `systemctl --user`（除非 WSL2 + systemd）。Windows 请改用 pi-web-ui 自带的服务化命令（等价于本仓库的 systemd 模板）：
  - `pi-web-ui server install --port 8787 --cwd "$USERPROFILE"` —— 写 HKCU Run 键，登录自启
  - `pi-web-ui server shortcut` —— 桌面一键启动图标
  - 管理：`pi-web-ui server status | restart | stop | uninstall`
  - 或 `./install.sh --windows-service` —— 让 install.sh 自动识别 Windows 并代跑 `server install`
- **GitHub token**：写入 `~/.bashrc` 后每个新终端生效。**Linux** 上 pi-web-ui 服务从 `~/.config/pi-web.env` 读取（systemd `EnvironmentFile`）；**Windows 没有这个机制** —— 服务化启动时进程环境不含 `~/.bashrc` 的 export，要么用 Git Bash 前台跑 `pi-web-ui`，要么把 `$env:GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."` 加进 `%APPDATA%\pi-web-ui\pi-web-ui.ps1` 再重启服务

### 后续同步

```bash
cd ~/pi-config
./sync.sh  # git pull + ./install.sh (幂等)
```