#!/usr/bin/env bash
#
# add-mcp.sh — 向 mcp/mcp.json.template 添加一个 MCP 服务器
#
# 用法:
#   ./add-mcp.sh --name <服务器名> \
#       (--package <npm包[@版本]> | --url <地址> | --entry '<JSON>') \
#       [--args "<追加参数>" | --args '["a","b"]'] \
#       [--env "K=V,K2=V2" | --env '{"K":"V"}'] \
#       [--test] [--timeout-ms <毫秒>] [--force] [--apply]
#
# 示例:
#   # npm 包服务器（npx 启动）
#   ./add-mcp.sh --name memory --package @modelcontextprotocol/server-memory \
#                --args '{{HOME}}/memory.json' --test --apply
#
#   # 远程 HTTP 服务器
#   ./add-mcp.sh --name docs --url https://mcp.example.com/mcp --test
#
#   # 完整自定义条目
#   ./add-mcp.sh --name foo \
#       --entry '{"command":"npx","args":["-y","some-server"],"env":{}}'
#
# 说明:
#   · --args 里可以用 {{HOME}} 这类占位符，安装时按各主机目录替换（可移植）
#   · --env 里的 ${VAR} 会被原样保留，由 pi-mcp-adapter 在运行时展开
#   · --test 在写入前先用 JSON-RPC 探测服务器能否启动并列出工具
#   · --apply 写入后立即运行 ./install.sh 让本机生效
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$REPO_DIR/mcp/mcp.json.template"
PROBE="$REPO_DIR/scripts/mcp-probe.mjs"

NAME=""
PACKAGE=""
URL=""
ENTRY=""
ARGS_RAW=""
ENV_RAW=""
TEST=0
FORCE=0
APPLY=0
TIMEOUT_MS=180000

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
err()   { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2; }

usage() {
  cat <<'EOF'
用法:
  ./add-mcp.sh --name <服务器名> \
      (--package <npm包[@版本]> | --url <地址> | --entry '<JSON>') \
      [--args "<追加参数>"] [--env "K=V,K2=V2"] \
      [--test] [--timeout-ms <毫秒>] [--force] [--apply] [-h]

选项:
  --name <名>          服务器配置名（字母/数字/_/-，如 filesystem、my-server）
  --package <包[@版本]>  npx 启动的 npm 包（自动生成 "npx -y <包>"; args 追加其后）
  --url <地址>          远程 HTTP MCP 服务器（StreamableHTTP）
  --entry '<JSON>'      直接给完整条目（最高优先级）
  --args "<参数>"       追加参数；支持 {{HOME}} 占位符
  --env "K=V,K2=V2"     环境变量（也可传 JSON 对象）
  --test                写入前先探测服务器能否启动并列出工具
  --timeout-ms <ms>     探测超时（默认 180000）
  --force               探测失败或同名已存在时仍继续
  --apply               写入后立即运行 ./install.sh
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --name)       NAME="${2:?--name 需要值}"; shift 2 ;;
    --package)    PACKAGE="${2:?--package 需要值}"; shift 2 ;;
    --url)        URL="${2:?--url 需要值}"; shift 2 ;;
    --entry)      ENTRY="${2:?--entry 需要值}"; shift 2 ;;
    --args)       ARGS_RAW="${2:?--args 需要值}"; shift 2 ;;
    --env)        ENV_RAW="${2:?--env 需要值}"; shift 2 ;;
    --test)       TEST=1; shift ;;
    --force)      FORCE=1; shift ;;
    --apply)      APPLY=1; shift ;;
    --timeout-ms) TIMEOUT_MS="${2:?--timeout-ms 需要值}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            err "未知选项: $1"; usage; exit 1 ;;
  esac
done

# ─────────── 校验 ───────────
if [[ -z "$NAME" ]]; then err "--name 必填"; usage; exit 1; fi
if [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  err "服务器名只能包含字母/数字/_/-（当前: $NAME）"; exit 1
fi

src_count=0
[[ -n "$PACKAGE" ]] && src_count=$((src_count + 1))
[[ -n "$URL" ]]     && src_count=$((src_count + 1))
[[ -n "$ENTRY" ]]   && src_count=$((src_count + 1))
if (( src_count != 1 )); then
  err "必须且只能指定一种来源: --package / --url / --entry"; exit 1
fi

# ─────────── 构建条目 JSON ───────────
build_entry() {
  PACKAGE="$PACKAGE" URL="$URL" ARGS_RAW="$ARGS_RAW" ENV_RAW="$ENV_RAW" node <<'NODE'
const { PACKAGE, URL, ARGS_RAW, ENV_RAW } = process.env;

let extraArgs = [];
if (ARGS_RAW) {
  extraArgs = ARGS_RAW.startsWith('[') ? JSON.parse(ARGS_RAW) : ARGS_RAW.split(/\s+/).filter(Boolean);
}

let env = {};
if (ENV_RAW) {
  if (ENV_RAW.startsWith('{')) {
    env = JSON.parse(ENV_RAW);
  } else {
    env = Object.fromEntries(
      ENV_RAW.split(',')
        .map((s) => { const i = s.indexOf('='); return i < 0 ? null : [s.slice(0, i).trim(), s.slice(i + 1).trim()]; })
        .filter(Boolean)
    );
  }
}

const entry = {};
if (URL) entry.url = URL;
else { entry.command = 'npx'; entry.args = ['-y', PACKAGE, ...extraArgs]; }
if (Object.keys(env).length) entry.env = env;

process.stdout.write(JSON.stringify(entry));
NODE
}

if [[ -n "$ENTRY" ]]; then
  entry_json="$ENTRY"
  if ! node -e 'JSON.parse(process.argv[1])' "$entry_json" >/dev/null 2>&1; then
    err "--entry 不是合法 JSON"; exit 1
  fi
else
  entry_json="$(build_entry)"
fi

echo "$BOLD${NAME}:$RESET ${entry_json}"

# ─────────── 探测（--test）───────────
if (( TEST )); then
  echo "▸ 探测中（超时 ${TIMEOUT_MS}ms）..."
  result="$(printf '%s' "$entry_json" | node "$PROBE" --name "$NAME" --timeout-ms "$TIMEOUT_MS" 2>/dev/null \
    || printf '{"ok":false,"error":"探测脚本执行失败"}')"
  isok="$(node -e 'console.log(JSON.parse(process.argv[1]).ok)' "$result" 2>/dev/null || echo false)"
  if [[ "$isok" == "true" ]]; then
    n="$(node -e 'console.log(JSON.parse(process.argv[1]).toolCount)' "$result")"
    tools="$(node -e 'console.log((JSON.parse(process.argv[1]).tools||[]).join(", "))' "$result")"
    ok "可用：${n} 个工具：${tools}"
  else
    em="$(node -e 'console.log(JSON.parse(process.argv[1]).error||"未知错误")' "$result" 2>/dev/null || echo 未知错误)"
    stderr="$(node -e 'const r=JSON.parse(process.argv[1]);console.log(r.stderr||"")' "$result" 2>/dev/null || true)"
    err "探测失败：$em"
    [[ -n "$stderr" ]] && printf '    服务器 stderr: %s\n' "$(printf '%s' "$stderr" | head -3)"
    if (( ! FORCE )); then
      err "已中止。修好参数后重试，或用 --force 忽略探测结果照常添加"
      exit 1
    fi
    warn "继续添加（--force）"
  fi
fi

# ─────────── 写入模板 ───────────
if ! FORCE="$FORCE" node -e '
  const fs = require("fs");
  const f = process.argv[1];
  const name = process.argv[2];
  const entry = JSON.parse(process.argv[3]);
  const force = process.env.FORCE === "1";
  const cfg = JSON.parse(fs.readFileSync(f, "utf8"));
  cfg.mcpServers = cfg.mcpServers || {};
  if (Object.prototype.hasOwnProperty.call(cfg.mcpServers, name) && !force) {
    console.error(`mcpServers.${name} 已存在（用 --force 覆盖）`);
    process.exit(1);
  }
  cfg.mcpServers[name] = entry;
  fs.writeFileSync(f, JSON.stringify(cfg, null, 2) + "\n");
  console.log(`✓ 已写入 mcpServers.${name}`);
' "$TPL" "$NAME" "$entry_json"; then
  exit 1
fi

# ─────────── 应用（--apply）───────────
if (( APPLY )); then
  echo "▸ 运行 install.sh 使本机生效..."
  "$REPO_DIR/install.sh"
fi

printf '\n%s 完成：%s\n' "$GREEN✓$RESET" "$NAME"
printf '  %s记得: git add -A && git commit && git push；其他主机 git pull 后重跑 ./install.sh 即生效%s\n' "$DIM" "$RESET"