#!/usr/bin/env bash
#
# verify.sh — push 前的完整性自检
#
#   · 探测 mcp.json.template 里每个服务器的可用性（JSON-RPC initialize + tools/list）
#   · 校验 skills/*/SKILL.md 的 frontmatter（name + description）
#   · 扫描疑似密钥
#
# 用法:
#   ./verify.sh           # 完整自检（含服务器探测，需要网络）
#   ./verify.sh --no-probe   # 跳过运行时探测（只做静态检查，快）
#   ./verify.sh --quiet      # 只打印失败项
#
# 任一检查失败 → 退出码 1
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$REPO_DIR/mcp/mcp.json.template"
PROBE="$REPO_DIR/scripts/mcp-probe.mjs"

NO_PROBE=0
QUIET=0

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
ok()  { (( QUIET )) || printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn(){ (( QUIET )) || printf '  %s•%s %s\n' "$YELLOW" "$RESET" "$1"; }
err() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"; }
section(){ printf '\n%s▸ %s%s\n' "$BOLD" "$1" "$RESET"; }

while (( $# > 0 )); do
  case "$1" in
    --no-probe) NO_PROBE=1; shift ;;
    --quiet)    QUIET=1; shift ;;
    -h|--help)  echo "用法: ./verify.sh [--no-probe] [--quiet]"; exit 0 ;;
    *)          err "未知选项: $1"; exit 1 ;;
  esac
done

fail=0

# ─────────── 渲染模板到临时文件（{{HOME}} 替换）───────────
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
TPL="$TPL" OUT="$TMP" node -e '
  const fs = require("fs");
  const src = fs.readFileSync(process.env.TPL, "utf8");
  const rendered = src.replace(/\{\{([A-Z0-9_]+)\}\}/g, (m, k) => process.env[k] ?? m);
  fs.writeFileSync(process.env.OUT, rendered);
'

# ─────────── MCP 服务器 ───────────
section "MCP 服务器（mcp/mcp.json.template）"
servers="$(node -e '
  const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  for (const k of Object.keys(c.mcpServers || {})) console.log(k);
' "$TMP")"

if [[ -z "$servers" ]]; then
  err "模板里没有任何 mcpServers"; exit 1
fi

while IFS= read -r name; do
  cfg="$(node -e '
    const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(JSON.stringify(c.mcpServers[process.argv[2]]));
  ' "$TMP" "$name")"

  if [[ "$cfg" != *'"command"'* ]]; then
    warn "$name（HTTP 服务器，跳过运行时探测）"
    continue
  fi

  if (( NO_PROBE )); then
    warn "$name（--no-probe 跳过探测）"
    continue
  fi

  out="$(printf '%s' "$cfg" | node "$PROBE" --name "$name" --timeout-ms 180000 2>/dev/null \
        || printf '{"ok":false,"error":"probe 脚本异常"}')"
  isok="$(node -e 'console.log(JSON.parse(process.argv[1]).ok)' "$out" 2>/dev/null || echo false)"

  if [[ "$isok" == "true" ]]; then
    n="$(node -e 'console.log(JSON.parse(process.argv[1]).toolCount)' "$out")"
    ok "$name（${n} 个工具）"
  else
    em="$(node -e 'console.log(JSON.parse(process.argv[1]).error || "未知错误")' "$out" 2>/dev/null || echo 未知错误)"
    err "$name — $em"
    fail=1
  fi
done <<< "$servers"

# ─────────── skills ───────────
section "skills（skills/*/SKILL.md）"
found=0
for d in "$REPO_DIR"/skills/*/; do
  [[ -d "$d" ]] || continue
  found=1
  nm="$(basename "$d")"
  if node -e '
    const fs = require("fs");
    const dir = process.argv[1];
    const f = dir + "/SKILL.md";
    if (!fs.existsSync(f)) process.exit(1);
    const s = fs.readFileSync(f, "utf8");
    const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(s);
    if (!m) process.exit(1);
    const fm = m[1];
    if (!/(?:^|\n)name:/.test(fm)) process.exit(1);
    if (!/(?:^|\n)description:/.test(fm)) process.exit(1);
  ' "$d" 2>/dev/null; then
    ok "$nm"
  else
    err "$nm — SKILL.md 缺失或 frontmatter 不完整（需 --- name / description ---）"
    fail=1
  fi
done
if (( ! found )); then
  err "skills/ 目录为空"
  fail=1
fi

# ─────────── 密钥扫描 ───────────
section "密钥扫描"
hits="$(grep -rInE \
  '(ghp_[a-zA-Z0-9]{20,}|sk-[a-zA-Z0-9]{20,}|AIza[a-zA-Z0-9_-]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN[^-]+PRIVATE KEY)' \
  "$REPO_DIR" --exclude-dir=.git 2>/dev/null || true)"
if [[ -n "$hits" ]]; then
  printf '%s\n' "$hits"
  err "发现疑似密钥，请移除后再 push"
  fail=1
else
  ok "未发现疑似密钥"
fi

# ─────────── 汇总 ───────────
echo
if (( fail )); then
  err "verify 未通过"
  exit 1
fi
printf '%s 全部通过，可以 push 🚀%s\n' "$GREEN" "$RESET"