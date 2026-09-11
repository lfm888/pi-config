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

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME_DIR/.pi-config-backup/$STAMP"

# ────────────────────────── 可调参数 ──────────────────────────
PI_WEB_PORT="${PI_WEB_PORT:-8787}"
PI_WEB_WORKSPACE="${PI_WEB_WORKSPACE:-$HOME_DIR}"

# ─────────────────────────── 开关 ───────────────────────────
DRY_RUN=0
SKIP_PACKAGES=0
SKIP_WEBUI=0
KEEP_LEGACY_SKILLS=0

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
  --skip-web-ui          跳过 pi-web-ui（npm 全局包 + systemd 服务）
  --keep-legacy-skills   保留 ~/.opencode/skills 等旧目录（默认从配置移除以免重复加载）
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
    --keep-legacy-skills) KEEP_LEGACY_SKILLS=1; shift ;;
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
section "1/6  环境检查"
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
section "2/6  备份现有配置"
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
render_template() {
  local tpl="$1" out="$2"
  if (( DRY_RUN )); then
    skip "[dry-run] 渲染 $(basename "$tpl") → $(tilde "$out")"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  TPL="$tpl" OUT="$out" node -e '
    const fs = require("fs");
    const src = fs.readFileSync(process.env.TPL, "utf8");
    const rendered = src.replace(/\{\{([A-Z0-9_]+)\}\}/g, (m, key) =>
      Object.prototype.hasOwnProperty.call(process.env, key) ? process.env[key] : m);
    fs.writeFileSync(process.env.OUT, rendered);
  '
}

# ══════════════════════════════════════════════════════════
section "3/6  安装 MCP 配置"
# ══════════════════════════════════════════════════════════

# 写入「对所有项目生效」的全局配置
# （不要放在 ~/.mcp.json —— 那是项目级路径，只在 cwd=$HOME 时生效）
render_template "$REPO_DIR/mcp/mcp.json.template" "$MCP_GLOBAL_FILE"
if (( ! DRY_RUN )); then
  ok "已写入全局 MCP 配置：$(tilde "$MCP_GLOBAL_FILE")"
fi

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

# ══════════════════════════════════════════════════════════
section "4/6  配置 skills 指向与 pi 设置"
# ══════════════════════════════════════════════════════════
if (( DRY_RUN )); then
  skip "[dry-run] 更新 $(tilde "$PI_SETTINGS")（skills 指向 + packages 合并）"
else
  if [[ ! -f "$PI_SETTINGS" ]]; then
    export REPO_DIR
    render_template "$REPO_DIR/pi/settings.json.template" "$PI_SETTINGS"
    ok "已创建 $(tilde "$PI_SETTINGS")（来自模板）"
  fi

  # 合并式更新：保留已有字段，只补充 skills 指向与 packages，避免覆盖你的其他设置
  GREEN="$GREEN" YELLOW="$YELLOW" DIM="$DIM" RESET="$RESET" \
  PI_SETTINGS="$PI_SETTINGS" REPO_DIR="$REPO_DIR" HOME_DIR="$HOME_DIR" \
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

    const WANT_PKGS = ["npm:pi-mcp-adapter", "npm:pi-web-access"];
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
section "5/6  安装 pi 包"
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
section "6/6  安装 pi-web-ui"
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

  # 6b. 用户级 systemd 服务（用户级无需 sudo）
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "未找到 systemctl —— 跳过服务安装，可前台启动：pi-web-ui"
  elif ! systemctl --user list-units >/dev/null 2>&1; then
    warn "用户级 systemd 不可用 —— 跳过服务安装，可前台启动：pi-web-ui"
  else
    PI_WEB_ENTRY="$(npm root -g 2>/dev/null)/pi-web-ui/dist/server/index.js"
    export NODE_BIN PI_WEB_ENTRY PI_WEB_PORT PI_WEB_WORKSPACE
    export LANG="${LANG:-C.UTF-8}"

    if [[ -f "$PI_WEB_ENTRY" ]]; then
      render_template "$REPO_DIR/pi-web-ui/pi-web-ui.service.template" "$UNIT_FILE"
      if (( ! DRY_RUN )); then
        ok "已写入服务单元：$(tilde "$UNIT_FILE")"
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
section "7/7  注册「输入 pi 自动打开 Web UI」"
# ══════════════════════════════════════════════════════════
if (( SKIP_WEBUI )); then
  skip "已跳过（--skip-web-ui）"
else
  SHELL_RC=""
  case "${SHELL:-}" in
    *zsh) SHELL_RC="$HOME_DIR/.zshrc" ;;
    *)    SHELL_RC="$HOME_DIR/.bashrc" ;;
  esac
  if [[ -z "$SHELL_RC" || ! -f "$SHELL_RC" ]]; then
    warn "未找到 shell 配置文件（$SHELL_RC），跳过 —— 可手动把 shell/pi-open-web.sh 内容追加到 rc 文件"
  else
    if grep -qF 'pi-config: pi → 打开 Web UI' "$SHELL_RC" 2>/dev/null; then
      skip "已注册过：$(tilde "$SHELL_RC")"
    elif (( DRY_RUN )); then
      skip "[dry-run] 追加 shell/pi-open-web.sh → $(tilde "$SHELL_RC")"
    else
      printf '\n' >> "$SHELL_RC"
      cat "$REPO_DIR/shell/pi-open-web.sh" >> "$SHELL_RC"
      ok "已注册（$(tilde "$SHELL_RC")）：输入 pi 打开 Web UI；pi-tui 进终端界面"
    fi
  fi
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
