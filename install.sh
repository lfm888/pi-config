#!/usr/bin/env bash
#
#  pi-config installer
#  在任意主机上复刻这套 pi 配置：MCP 服务器 / skills / pi 包 / pi-web-ui
#
#  设计要点：
#    · 幂等 —— 可安全重复执行
#    · 自动备份被修改的文件到 ~/.pi-config-backup/<时间戳>/
#    · --dry-run 预览所有操作
#
set -euo pipefail

# ─────────────────────────── 路径 ───────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME_DIR/.pi/agent}"
PI_SETTINGS="$PI_AGENT_DIR/settings.json"
MCP_GLOBAL_FILE="$HOME_DIR/.config/mcp/mcp.json"
LEGACY_MCP_FILE="$HOME_DIR/.mcp.json"
UNIT_FILE="$HOME_DIR/.config/systemd/user/pi-web-ui.service"
PI_WEB_ENV_FILE="$HOME_DIR/.config/pi-web.env"
SHELL_RC=""
case "${SHELL:-}" in
  *zsh) SHELL_RC="$HOME_DIR/.zshrc" ;;
  *)    SHELL_RC="$HOME_DIR/.bashrc" ;;
esac

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME_DIR/.pi-config-backup/$STAMP"

# ────────────────────────── 可调参数 ──────────────────────────
PI_WEB_PORT="${PI_WEB_PORT:-8787}"
PI_WEB_WORKSPACE="${PI_WEB_WORKSPACE:-$HOME_DIR}"

# ─────────────────────────── 平台判定 ───────────────────────────
# Windows（Git Bash/MSYS/Cygwin）没有 systemd，服务化改走 pi-web-ui 自带命令
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
  *)                    IS_WINDOWS=0 ;;
esac

# Windows 下把 Git Bash 的 MSYS 路径（/c/x）转成 Windows 混合路径（C:/x）
# —— pi-web-ui / pi / node / npm 都是 Windows 程序，不认 /c/... 这种写法
win_path() {
  if (( IS_WINDOWS )) && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    printf '%s' "$1"
  fi
}

# ──────────── MCP 服务器：本地自包含安装（filesystem 专用）────────────
# 为什么 filesystem 不走 npx：npx 只能指定一个包名，管不住传递依赖。
# npm 会把它的 zod 解析成 4.x，而该服务器用 zod-to-json-schema@3 生成工具 schema，
# zod 4 下会产出缺 type 的非法 JSON Schema → 客户端报
# “Invalid result for tools/list: ... inputSchema.type expected object”。
# 显式把 zod 钉住、用 node 直跑 dist/index.js 才能真正稳定。
MCP_SERVERS_DIR="$HOME_DIR/.pi/mcp-servers"
MCP_FILESYSTEM_PKGS="@modelcontextprotocol/server-filesystem@2026.8.31 @modelcontextprotocol/sdk@1.30.0 zod@4.6.5"

# ─────────────────────────── 开关 ───────────────────────────
DRY_RUN=0
SKIP_PACKAGES=0
SKIP_WEBUI=0
KEEP_LEGACY_SKILLS=0
# MCP 写入策略：merge（默认，模板为准 + 保留本机独有）| keep-local（只补缺失，不动已有）| reset（完全覆盖）
MCP_MODE="merge"
# Windows 上是否代为安装 pi-web-ui 自启服务（HKCU Run 键）：默认只提示，加 --windows-service 才执行
WINDOWS_SERVICE=0

# ─────────────────────────── 输出 ───────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=''; DIM=''; GREEN=''; YELLOW=''; RED=''; RESET=''
fi

ok()      { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
skip()    { printf '  %s• %s%s\n' "$DIM" "$1" "$RESET"; }
warn()    { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
err()     { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2; }
section() { printf '\n%s▸ %s%s\n' "$BOLD" "$1" "$RESET"; }
run()     { if (( DRY_RUN )); then printf '  %s[dry-run] %s%s\n' "$DIM" "$*" "$RESET"; else "$@"; fi; }
tilde()   { printf '%s' "${1/#$HOME_DIR/\~}"; }

usage() {
  cat <<'EOF'
pi-config installer — 复刻 pi 的 MCP / skills / 包 / Web UI 配置

用法:
  ./install.sh [选项]

选项:
  --dry-run              只打印将要执行的操作，不修改任何文件
  --skip-packages        跳过 pi 包安装
  --skip-web-ui          跳过 pi-web-ui（npm 全局包 + 服务化）
  --windows-service      Windows：代为执行 pi-web-ui server install（HKCU Run 键开机自启）
  --keep-legacy-skills   保留 ~/.opencode/skills 等旧目录（默认从配置移除以免重复加载）
  --mcp-mode <mode>      MCP 配置写入策略（默认 merge）：
                           merge       模板里定义过的服务器以模板为准；本机额外添加的保留；差异全部打印
                           keep-local  只补齐本机还没有的服务器；已存在的条目一律不动（保护本机热修）
                           reset       完全以模板覆盖（旧行为）
  --port <n>             pi-web-ui 端口（默认 8787）
  --workspace <dir>      pi-web-ui 工作目录（默认 $HOME）
  -h, --help             显示本帮助

环境变量:
  PI_CODING_AGENT_DIR    pi 配置目录（默认 ~/.pi/agent）
  PI_WEB_PORT            同 --port
  PI_WEB_WORKSPACE       同 --workspace
EOF
}

# ────────────────────────── 参数解析 ──────────────────────────
while (( $# > 0 )); do
  case "$1" in
    --dry-run)            DRY_RUN=1; shift ;;
    --skip-packages)      SKIP_PACKAGES=1; shift ;;
    --skip-web-ui)        SKIP_WEBUI=1; shift ;;
    --windows-service)    WINDOWS_SERVICE=1; shift ;;
    --keep-legacy-skills) KEEP_LEGACY_SKILLS=1; shift ;;
    --mcp-mode)           MCP_MODE="${2:?--mcp-mode 需要一个值}"; shift 2 ;;
    --port)               PI_WEB_PORT="${2:?--port 需要一个值}"; shift 2 ;;
    --workspace)          PI_WEB_WORKSPACE="${2:?--workspace 需要一个值}"; shift 2 ;;
    -h|--help)            usage; exit 0 ;;
    *)                    err "未知选项: $1"; usage; exit 1 ;;
  esac
done

printf '\n%s pi-config 安装器%s\n' "$BOLD" "$RESET"
printf '  仓库位置: %s\n' "$REPO_DIR"
if (( DRY_RUN )); then
  warn "DRY-RUN 模式 —— 不会修改任何文件"
fi

# ══════════════════════════════════════════════════════════
section "1/7  环境检查"
# ══════════════════════════════════════════════════════════
missing=0
for c in node npm pi; do
  if command -v "$c" >/dev/null 2>&1; then
    ok "$c"
  else
    err "未找到 $c"
    missing=1
  fi
done
if (( missing )); then
  err "请先安装上列缺失依赖后再运行"
  exit 1
fi

NODE_BIN="$(command -v node)"
node_major="$(node -p 'process.versions.node.split(".")[0]')"
node_minor="$(node -p 'process.versions.node.split(".")[1]')"
if (( node_major < 22 || (node_major == 22 && node_minor < 19) )); then
  err "Node 版本过低：pi-web-ui 需 >= 22.19，当前 $(node -v)"
  exit 1
fi
ok "node $(node -v)  /  npm $(npm -v)  /  pi $(pi --version 2>/dev/null | tail -1 || echo '?')"

# ══════════════════════════════════════════════════════════
section "2/7  备份现有配置"
# ══════════════════════════════════════════════════════════
backup_if_exists() {
  local f="$1"
  if [[ ! -e "$f" ]]; then
    skip "不存在，跳过：$(tilde "$f")"
    return 0
  fi
  if (( DRY_RUN )); then
    skip "[dry-run] 备份 $(tilde "$f")"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  cp -a "$f" "$BACKUP_DIR/"
  ok "已备份：$(tilde "$f")"
}

backup_if_exists "$MCP_GLOBAL_FILE"
backup_if_exists "$PI_SETTINGS"
backup_if_exists "$LEGACY_MCP_FILE"

# 模板渲染：把 {{VAR}} 替换为同名环境变量的值
# 注意：只处理双花括号，因此 ${GITHUB_PERSONAL_ACCESS_TOKEN} 这类
#       「运行时插值」会被原样保留（由 pi-mcp-adapter 在启动服务器时展开）
# 渲染后若仍残留 {{...}}（模板写法与渲染器不兼容）会直接报错退出，
# 避免把「字面量占位符」当路径写进本机配置
# 模板渲染：把 {{VAR}} 替换为同名环境变量的值（统一走 scripts/render-template.mjs，
# 与 verify.sh 共用一份实现，避免两处漂移）
#   $3=1 表示目标是 JSON：会对注入值做 JSON 转义，并把 MSYS 路径 /c/x 转成 C:/x
# 渲染失败（如残留不受支持的 {{VAR||默认值}}）会直接报错退出，不写出坏配置
render_template() {
  local tpl="$1" out="$2" json="${3:-0}" mode=""
  [[ "$json" == "1" ]] && mode="--json"
  if ! node "$REPO_DIR/scripts/render-template.mjs" "$tpl" "$out" $mode; then
    err "模板渲染失败：$(basename "$tpl")"
    exit 1
  fi
}

# ══════════════════════════════════════════════════════════
section "3/7  安装 MCP 配置"
# ══════════════════════════════════════════════════════════

# 探测本机 Chrome/Chromium 可执行文件；找到则打印绝对路径并返回 0
# 说明：chrome-devtools-mcp 默认只认系统 Chrome（Linux 上是 /opt/google/chrome/chrome），
#       Chromium / snap 安装 / Edge 等一律找不到 —— 需要在启动参数里显式给 --executablePath。
detect_chrome() {
  local c p
  # 1) PATH 中的常见命令名（Linux / macOS；Windows Git Bash 也会命中 PATH 条目）
  for c in google-chrome google-chrome-stable chromium chromium-browser \
           brave-browser microsoft-edge microsoft-edge-stable; do
    if command -v "$c" >/dev/null 2>&1; then
      command -v "$c"; return 0
    fi
  done
  # 2) 常见固定安装路径（含 Windows Git Bash 的 /c/... 写法）
  local candidates="/opt/google/chrome/chrome
/snap/bin/chromium
/usr/lib/chromium-browser/chromium-browser
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome
$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if (( IS_WINDOWS )); then
    candidates="/c/Program Files/Google/Chrome/Application/chrome.exe
/c/Program Files (x86)/Google/Chrome/Application/chrome.exe
/c/Program Files/Microsoft/Edge/Application/msedge.exe
/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe
$candidates"
  fi
  while IFS= read -r p; do
    if [[ -n "$p" && -x "$p" ]]; then printf '%s' "$p"; return 0; fi
  done <<< "$candidates"
  return 1
}

# 3a. filesystem 服务器：本地自包含安装（目录在仓库外，~/.pi/mcp-servers）
WIN_MCP_DIR="$(win_path "$MCP_SERVERS_DIR")"
if node -e '
  const fs = require("fs");
  const want = { zod: "4.6.5", "@modelcontextprotocol/server-filesystem": "2026.8.31" };
  for (const [name, ver] of Object.entries(want)) {
    const p = process.argv[1] + "/node_modules/" + name + "/package.json";
    if (!fs.existsSync(p)) process.exit(1);
    if (JSON.parse(fs.readFileSync(p, "utf8")).version !== ver) process.exit(1);
  }
' "$WIN_MCP_DIR" 2>/dev/null; then
  skip "filesystem 服务器已就绪（$MCP_SERVERS_DIR）"
elif (( DRY_RUN )); then
  skip "[dry-run] npm i --prefix <~/.pi/mcp-servers> $MCP_FILESYSTEM_PKGS"
else
  mkdir -p "$MCP_SERVERS_DIR"
  if npm i --prefix "$WIN_MCP_DIR" $MCP_FILESYSTEM_PKGS >/dev/null 2>&1; then
    ok "已安装 filesystem 服务器（2026.8.31 + zod 4.6.5）"
  else
    warn "filesystem 服务器安装失败，可手动重试："
    echo "        npm i --prefix \"$WIN_MCP_DIR\" $MCP_FILESYSTEM_PKGS"
  fi
fi
export MCP_SERVERS_DIR

# 渲染模板到临时文件（即使 --dry-run 也要渲染，才能算出「将要发生什么」）
TMP_MCP="$(mktemp)"
trap 'rm -f "$TMP_MCP"' EXIT
render_template "$REPO_DIR/mcp/mcp.json.template" "$TMP_MCP" 1

# 写入「对所有项目生效」的全局配置
# （不要放在 ~/.mcp.json —— 那是项目级路径，只在 cwd=$HOME 时生效）
# 合并策略见 --mcp-mode：默认绝不静默丢弃本机配置
TPL_RENDERED="$TMP_MCP" MCP_FILE="$MCP_GLOBAL_FILE" MCP_MODE="$MCP_MODE" MCP_DRYRUN="$DRY_RUN" \
GREEN="$GREEN" YELLOW="$YELLOW" DIM="$DIM" RESET="$RESET" \
node -e '
  const fs = require("fs");
  const path = require("path");
  const G = process.env.GREEN, Y = process.env.YELLOW, D = process.env.DIM, R = process.env.RESET;
  const tpl = JSON.parse(fs.readFileSync(process.env.TPL_RENDERED, "utf8"));
  const target = process.env.MCP_FILE;
  const mode = process.env.MCP_MODE || "merge";
  const dry = process.env.MCP_DRYRUN === "1";

  let cur = { mcpServers: {} };
  if (fs.existsSync(target)) {
    try {
      cur = JSON.parse(fs.readFileSync(target, "utf8"));
    } catch (e) {
      console.error(`  ${Y}!${R} 现有 ${target} 不是合法 JSON：${e.message}`);
      process.exit(1);
    }
  }
  if (!cur.mcpServers || typeof cur.mcpServers !== "object") cur.mcpServers = {};

  const tplServers = tpl.mcpServers || {};
  const tplNames = new Set(Object.keys(tplServers));
  const added = [], updated = [], same = [], keptLocal = [];
  const localOnly = Object.keys(cur.mcpServers).filter((n) => !tplNames.has(n));

  for (const [name, def] of Object.entries(tplServers)) {
    if (!Object.prototype.hasOwnProperty.call(cur.mcpServers, name)) {
      cur.mcpServers[name] = def;
      added.push(name);
      continue;
    }
    if (JSON.stringify(cur.mcpServers[name]) === JSON.stringify(def)) {
      same.push(name);
      continue;
    }
    if (mode === "keep-local") {
      keptLocal.push(name);
      continue;
    }
    cur.mcpServers[name] = def;
    updated.push(name);
  }
  if (mode === "reset") for (const n of localOnly) delete cur.mcpServers[n];

  const line = (label, arr) => { if (arr.length) console.log(`  ${G}✓${R} ${label}：${arr.join(", ")}`); };
  line("新增服务器", added);
  line("按模板更新", updated);
  line("保留本机版本（模板已改）", keptLocal);
  line("无变化", same);
  if (mode === "reset") {
    if (localOnly.length) console.log(`  ${Y}!${R} reset 模式：移除本机独有服务器 ${localOnly.join(", ")}`);
  } else {
    line("保留本机独有服务器", localOnly);
  }

  if (dry) {
    console.log(`  ${D}• [dry-run] 不写入 ${target}（以上是即将发生的变化）${R}`);
    process.exit(0);
  }
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify(cur, null, 2) + "\n");
  console.log(`  ${G}✓${R} 已写入 ${target}（策略：${mode}）`);
'

# 移除会遮蔽全局配置的旧文件
# 优先级（后者覆盖前者）：~/.config/mcp/mcp.json  <  <cwd>/.mcp.json
if [[ -e "$LEGACY_MCP_FILE" ]]; then
  warn "发现 ~/.mcp.json —— 该项目级配置会遮蔽全局配置，必须移除"
  if (( DRY_RUN )); then
    skip "[dry-run] 删除 ~/.mcp.json（已备份）"
  else
    rm -f "$LEGACY_MCP_FILE"
    ok "已删除 ~/.mcp.json（备份于 $(tilde "$BACKUP_DIR")）"
  fi
else
  skip "无残留的 ~/.mcp.json"
fi

# 3d. chrome-devtools：把探测到的浏览器可执行路径写入本机 MCP 配置
#     模板保持干净可移植（不含机器相关路径），这里做「本机增强」；
#     探测不到就维持默认自动探测，不阻塞安装。
CHROME_EXE="$(detect_chrome || true)"
if [[ -z "$CHROME_EXE" ]]; then
  warn "未找到 Chrome/Chromium —— chrome-devtools 的浏览器工具将不可用"
  skip "  安装 Chrome/Chromium（或 Linux 的 chromium/chromium-browser）后重跑本脚本即可"
elif (( DRY_RUN )); then
  skip "[dry-run] chrome-devtools 将使用浏览器：$CHROME_EXE"
else
  CHROME_EXE="$(win_path "$CHROME_EXE")"
  CHROME_EXE="$CHROME_EXE" MCP_FILE="$MCP_GLOBAL_FILE" \
  GREEN="$GREEN" YELLOW="$YELLOW" DIM="$DIM" RESET="$RESET" \
  node -e '
    const fs = require("fs");
    const G = process.env.GREEN, Y = process.env.YELLOW, D = process.env.DIM, R = process.env.RESET;
    const file = process.env.MCP_FILE, exe = process.env.CHROME_EXE;
    const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
    const s = cfg.mcpServers && cfg.mcpServers["chrome-devtools"];
    if (!s) { console.log(`  ${D}• 未配置 chrome-devtools，跳过浏览器路径注入${R}`); process.exit(0); }
    s.args = Array.isArray(s.args) ? s.args : [];
    const cur = s.args.find((a) => String(a).startsWith("--executablePath"));
    const curPath = cur ? String(cur).replace(/^--executablePath=?/, "") : null;
    if (curPath && fs.existsSync(curPath)) {
      console.log(`  ${D}• chrome-devtools 已指向存在的浏览器：${curPath}${R}`);
      process.exit(0);
    }
    s.args = s.args.filter((a) => !String(a).startsWith("--executablePath"));
    s.args.push(`--executablePath=${exe}`);
    fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
    console.log(`  ${G}✓${R} chrome-devtools 使用浏览器：${exe}`);
  '
fi

# ══════════════════════════════════════════════════════════
section "4/7  配置 skills 指向与 pi 设置"
# ══════════════════════════════════════════════════════════
if (( DRY_RUN )); then
  skip "[dry-run] 更新 $(tilde "$PI_SETTINGS")（skills 指向 + packages 合并）"
else
  if [[ ! -f "$PI_SETTINGS" ]]; then
    export REPO_DIR
    render_template "$REPO_DIR/pi/settings.json.template" "$PI_SETTINGS" 1
    ok "已创建 $(tilde "$PI_SETTINGS")（来自模板）"
  fi

  # 合并式更新：保留已有字段，只补充 skills 指向与 packages，避免覆盖你的其他设置
  GREEN="$GREEN" YELLOW="$YELLOW" DIM="$DIM" RESET="$RESET" \
  PI_SETTINGS="$PI_SETTINGS" REPO_DIR="$REPO_DIR" HOME_DIR="$HOME_DIR" \
  PKGS_FILE="$REPO_DIR/pi/packages.txt" \
  KEEP_LEGACY="$KEEP_LEGACY_SKILLS" \
  node -e '
    const fs = require("fs");
    const { PI_SETTINGS: file, REPO_DIR: repo, HOME_DIR: home } = process.env;
    const G = process.env.GREEN, Y = process.env.YELLOW, D = process.env.DIM, R = process.env.RESET;

    let cfg = {};
    if (fs.existsSync(file)) {
      const raw = fs.readFileSync(file, "utf8").trim();
      if (raw) {
        try {
          cfg = JSON.parse(raw);
        } catch (e) {
          console.error(`  ${Y}!${R} 现有 settings.json 不是合法 JSON：${e.message}`);
          process.exit(1);
        }
      }
    }

    const skillsDir = `${repo}/skills`;

    // 旧的 opencode skills 目录会让同名 skill 被加载两次 —— 默认移除
    const LEGACY = ["~/.config/opencode/skills", "~/.opencode/skills"];
    const isLegacy = (p) => LEGACY.some((l) => l === p || l.replace(/^~/, home) === p);

    let skills = Array.isArray(cfg.skills) ? cfg.skills.slice() : [];
    const removed = [];
    if (process.env.KEEP_LEGACY !== "1") {
      skills = skills.filter((s) => {
        if (isLegacy(s)) { removed.push(s); return false; }
        return true;
      });
    }
    if (!skills.includes(skillsDir)) skills.push(skillsDir);
    cfg.skills = skills;

    // 包列表的唯一真源是 pi/packages.txt（避免两处维护漂移）
    const WANT_PKGS = fs.existsSync(process.env.PKGS_FILE)
      ? fs.readFileSync(process.env.PKGS_FILE, "utf8")
          .split(/\r?\n/)   // 兼容 CRLF：否则行尾 \r 会让下面的 # 注释剥离失败
          .map((l) => l.replace(/#.*$/, "").trim())
          .filter(Boolean)
      : [];
    const curPkgs = Array.isArray(cfg.packages) ? cfg.packages : [];
    cfg.packages = Array.from(new Set([...curPkgs, ...WANT_PKGS]));

    if (!cfg.theme) cfg.theme = "dark";

    fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");

    console.log(`  ${G}✓${R} skills 指向：${skillsDir}`);
    for (const s of removed) {
      console.log(`  ${Y}!${R} 已移除重复的旧 skills 目录：${s}`);
    }
    if (removed.length) {
      console.log(`  ${D}• 磁盘上的旧目录未删除，如需清理可手动 rm -rf${R}`);
    }
    console.log(`  ${G}✓${R} packages：${cfg.packages.join(", ")}`);
  '
fi

# ══════════════════════════════════════════════════════════
section "5/7  安装 pi 包"
# ══════════════════════════════════════════════════════════
if (( SKIP_PACKAGES )); then
  skip "已跳过（--skip-packages）"
else
  installed_list="$(pi list 2>/dev/null || true)"
  while IFS= read -r pkg; do
    pkg="${pkg%%#*}"                                    # 去注释
    pkg="$(printf '%s' "$pkg" | tr -d '[:space:]')"      # 去空白
    [[ -z "$pkg" ]] && continue

    if printf '%s' "$installed_list" | grep -qF -- "$pkg"; then
      skip "已安装：$pkg"
    elif (( DRY_RUN )); then
      skip "[dry-run] pi install $pkg"
    elif pi install "$pkg" >/dev/null 2>&1; then
      ok "已安装：$pkg"
    else
      warn "安装失败：$pkg（可手动重试 pi install $pkg）"
    fi
  done < "$REPO_DIR/pi/packages.txt"
fi

# ══════════════════════════════════════════════════════════
section "6/7  安装 pi-web-ui"
# ══════════════════════════════════════════════════════════
if (( SKIP_WEBUI )); then
  skip "已跳过（--skip-web-ui）"
else
  # 6a. npm 全局包
  if command -v pi-web-ui >/dev/null 2>&1; then
    skip "已安装：pi-web-ui $(pi-web-ui --version 2>/dev/null | tail -1 || echo '')"
  else
    # node-pty 是原生模块，必须允许其安装脚本（否则内置终端不可用）
    run npm i -g --allow-scripts=node-pty,@google/genai,protobufjs pi-web-ui
    if (( ! DRY_RUN )); then
      ok "已安装 pi-web-ui"
    fi
  fi

  # 6b. 服务化
  #     Linux   → 用户级 systemd 单元（本仓库 pi-web-ui/pi-web-ui.service.template）
  #     Windows → pi-web-ui 自带 server install（HKCU Run 键 + wscript 无黑窗启动）
  if (( IS_WINDOWS )); then
    WIN_WORKSPACE="$(win_path "$PI_WEB_WORKSPACE")"
    if (( WINDOWS_SERVICE )); then
      if (( DRY_RUN )); then
        skip "[dry-run] pi-web-ui server install --port $PI_WEB_PORT --cwd $WIN_WORKSPACE"
      elif run pi-web-ui server install --port "$PI_WEB_PORT" --cwd "$WIN_WORKSPACE" >/dev/null 2>&1; then
        ok "Windows 自启服务已安装（HKCU Run 键）：http://127.0.0.1:$PI_WEB_PORT"
      else
        warn "server install 失败 —— 可手动执行：pi-web-ui server install --port $PI_WEB_PORT --cwd \"$WIN_WORKSPACE\""
      fi
    else
      skip "Windows：跳过 systemd（仓库的 systemd 模板只用于 Linux）"
      echo "       需要开机自启/桌面图标时执行："
      echo "         pi-web-ui server install --port $PI_WEB_PORT --cwd \"$WIN_WORKSPACE\"   # HKCU Run 键，登录自启"
      echo "         pi-web-ui server shortcut                                                 # 桌面一键启动图标"
      echo "       或给本脚本加 --windows-service 让它代跑 server install"
    fi
  elif ! command -v systemctl >/dev/null 2>&1; then
    warn "未找到 systemctl —— 跳过服务安装，可前台启动：pi-web-ui"
  elif ! systemctl --user list-units >/dev/null 2>&1; then
    warn "用户级 systemd 不可用 —— 跳过服务安装，可前台启动：pi-web-ui"
  else
    PI_WEB_ENTRY="$(npm root -g 2>/dev/null)/pi-web-ui/dist/server/index.js"
    export NODE_BIN PI_WEB_ENTRY PI_WEB_PORT PI_WEB_WORKSPACE
    export LANG="${LANG:-C.UTF-8}"

    if [[ -f "$PI_WEB_ENTRY" ]]; then
      if (( DRY_RUN )); then
        skip "[dry-run] 渲染 pi-web-ui.service → $(tilde "$UNIT_FILE")"
      else
        render_template "$REPO_DIR/pi-web-ui/pi-web-ui.service.template" "$UNIT_FILE"
        ok "已写入服务单元：$(tilde "$UNIT_FILE")"
      fi
      # 服务环境变量文件（systemd 服务不读 ~/.bashrc，github MCP 的 token 从这里取）
      if [[ -f "$PI_WEB_ENV_FILE" ]]; then
        skip "已存在：$(tilde "$PI_WEB_ENV_FILE")"
      elif (( DRY_RUN )); then
        skip "[dry-run] 生成 $(tilde "$PI_WEB_ENV_FILE")"
      else
        mkdir -p "$HOME_DIR/.config"
        src_token="$(sed -n 's/.*GITHUB_PERSONAL_ACCESS_TOKEN="\([^"]*\)".*/\1/p' "$SHELL_RC" 2>/dev/null | head -1)"
        {
          echo "# pi-web-ui 服务环境变量（由 pi-config 生成；此文件勿提交到任何仓库）"
          echo "# systemd 服务不读 ~/.bashrc，github MCP 的 token 从这里读取"
          if [[ -n "$src_token" && "$src_token" != *你* ]]; then
            echo "# 已自动从 $(tilde "$SHELL_RC") 迁移："
            echo "GITHUB_PERSONAL_ACCESS_TOKEN=\"$src_token\""
          else
            echo "# 请编辑本文件填入你的 GitHub token："
            echo '# GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxx"'
          fi
        } > "$PI_WEB_ENV_FILE"
        chmod 600 "$PI_WEB_ENV_FILE"
        ok "已生成 $(tilde "$PI_WEB_ENV_FILE")（600 权限）"
      fi
      run systemctl --user daemon-reload
      run systemctl --user enable --now pi-web-ui
      if (( ! DRY_RUN )) && systemctl --user is-active --quiet pi-web-ui; then
        ok "服务运行中：http://127.0.0.1:$PI_WEB_PORT"
      fi
    else
      warn "未找到 pi-web-ui 入口（$PI_WEB_ENTRY），跳过服务安装"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════
section "7/7  清理历史钩子（pi 保持终端 TUI）"
# ══════════════════════════════════════════════════════════
# 历史版本会往 shell 配置追加一段覆盖 `pi` 命令的钩子（输入 pi 自动打开 Web UI）。
# 现在改成：pi = 终端 TUI（原生行为，不覆盖）；pi-web-ui = 浏览器界面。
# 这里把旧钩子（标记块）从 shell 配置里清掉，幂等。
if [[ -z "$SHELL_RC" || ! -f "$SHELL_RC" ]]; then
  skip "无 shell 配置文件（$SHELL_RC），跳过"
elif ! grep -qF 'pi-config: pi → 打开 Web UI' "$SHELL_RC" 2>/dev/null; then
  skip "无历史钩子：$(tilde "$SHELL_RC")"
elif (( DRY_RUN )); then
  skip "[dry-run] 从 $(tilde "$SHELL_RC") 移除历史钩子标记块"
else
  SHELL_RC="$SHELL_RC" node -e '
    const fs = require("fs");
    const file = process.env.SHELL_RC;
    const src = fs.readFileSync(file, "utf8");
    const eol = src.includes("\r\n") ? "\r\n" : "\n";
    const kept = [];
    let inside = false;
    for (const line of src.split(/\r?\n/)) {
      if (!inside && line.includes("pi-config: pi → 打开 Web UI")) { inside = true; continue; }
      if (inside) {
        if (line.includes("pi-config: end")) inside = false;
        continue;
      }
      kept.push(line);
    }
    while (kept.length && kept[kept.length - 1].trim() === "") kept.pop();
    fs.writeFileSync(file, kept.join(eol) + eol);
  '
  ok "已移除历史钩子：$(tilde "$SHELL_RC")（pi 恢复为终端 TUI）"
fi

# ══════════════════════════════════════════════════════════
section "完成"
# ══════════════════════════════════════════════════════════
cat <<EOF

  已部署：
    MCP 配置     $(tilde "$MCP_GLOBAL_FILE")
    pi 设置      $(tilde "$PI_SETTINGS")
    skills       $REPO_DIR/skills
    pi-web-ui    http://127.0.0.1:$PI_WEB_PORT

EOF

if (( ! DRY_RUN )) && [[ -d "$BACKUP_DIR" ]]; then
  printf '  备份目录：%s\n\n' "$(tilde "$BACKUP_DIR")"
fi

printf '%s  还需手动完成：%s\n' "$BOLD" "$RESET"

step=1
if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
  warn "环境变量 GITHUB_PERSONAL_ACCESS_TOKEN 未设置 → github MCP 服务器不可用"
  cat <<'EOF'
      设置方法（追加到 ~/.bashrc 后重开终端）：
        export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxxxxxxxxxxx"
      Token 生成：GitHub → Settings → Developer settings
                 → Personal access tokens → Tokens (classic)，勾选 repo
EOF
  step=2
fi

cat <<EOF
  $step. 在 pi 中执行 /reload 使 MCP 配置生效，然后 /mcp 检查四个服务器状态
  $((step + 1)). 若默认模型不可用，先配置凭证：pi auth
EOF

printf '\n'
