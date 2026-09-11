#!/usr/bin/env bash
#
# add-skill.sh — 把本地目录或 GitHub 仓库的 skill 添加进 skills/
#
# 用法:
#   ./add-skill.sh --source <本地目录 | GitHub仓库 | 完整URL> [--name <名>] [--ref <分支/tag>] [--force] [--commit]
#
# 示例:
#   # 本地目录
#   ./add-skill.sh --source ~/下载/some-skill --name some-skill
#
#   # GitHub 仓库（整个仓库就是一个 skill）
#   ./add-skill.sh --source github.com/owner/some-skill
#
#   # GitHub 仓库的子目录（仓库里 skills/<x>/ 那种）
#   ./add-skill.sh --source github.com/owner/big-repo/sub/dir
#
#   # 指定分支 + 添加后立即提交
#   ./add-skill.sh --source github.com/owner/some-skill --ref main --commit
#
# 校验: 要求最终目录里有 SKILL.md，且 frontmatter 含 name 与 description
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_DIR/skills"

NAME=""
SOURCE=""
REF=""
FORCE=0
COMMIT=0

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'
YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
err()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1" >&2; }

usage() {
  cat <<'EOF'
用法:
  ./add-skill.sh --source <来源> [--name <名>] [--ref <分支/tag>] [--force] [--commit] [-h]

来源（--source）可以是:
  本地目录           ~/下载/foo
  GitHub 仓库        github.com/owner/repo          （或 owner/repo）
  GitHub 子目录      github.com/owner/big/sub/dir
  完整链接           https://github.com/owner/repo/tree/main/skills/foo

选项:
  --name <名>   技能目录名（默认取来源目录名；需 字母/数字/_/-）
  --ref <ref>   克隆指定的分支或 tag（默认默认分支）
  --force       已存在同名时覆盖
  --commit      添加后自动 git add + commit
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --source) SOURCE="${2:?--source 需要值}"; shift 2 ;;
    --name)   NAME="${2:?--name 需要值}"; shift 2 ;;
    --ref)    REF="${2:?--ref 需要值}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    --commit) COMMIT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)        err "未知选项: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$SOURCE" ]]; then err "--source 必填"; usage; exit 1; fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ─────────── 克隆：git(HTTP/1.1) 优先，codeload tarball 兜底 ───────────
clone_repo() {
  local spec="$1" ref="$2" dest="$3"
  local ref_args=()
  [[ -n "$ref" ]] && ref_args=(--branch "$ref")

  # 首选 git clone（HTTP/1.1 规避 HTTP/2 流不稳定问题）
  if git -c http.version=HTTP/1.1 clone --quiet --depth 1 "${ref_args[@]}" \
      "https://github.com/$spec" "$dest" 2>/dev/null; then
    return 0
  fi

  # 兜底：codeload tarball（curl 更抗网络抖动）
  local refs=()
  if [[ -n "$ref" ]]; then
    refs=("$ref")
  else
    refs=(refs/heads/main refs/heads/master)
  fi
  local r
  for r in "${refs[@]}"; do
    if curl -fsSL -o "$dest.tar.gz" "https://codeload.github.com/$spec/tar.gz/$r" 2>/dev/null; then
      mkdir -p "$dest"
      tar xzf "$dest.tar.gz" -C "$dest" --strip-components=1
      rm -f "$dest.tar.gz"
      return 0
    fi
  done
  return 1
}

# ─────────── 解析来源 ───────────
REPO_SPEC=""
SUB=""

if [[ -d "$SOURCE" ]]; then
  # 本地目录
  SRC_DIR="$SOURCE"
  ok "来源：本地目录 $SOURCE"
else
  # 归一化 GitHub 链接（去掉协议与 github.com 主机前缀）
  spec="$SOURCE"
  if [[ "$spec" =~ ^https?://(www\.)?github\.com/(.+)$ ]]; then
    spec="${BASH_REMATCH[2]}"
  elif [[ "$spec" =~ ^github\.com/(.+)$ ]]; then
    spec="${BASH_REMATCH[1]}"
  fi

  if [[ "$spec" =~ ^([^/]+/[^/]+)/tree/([^/]+)(/(.*))?$ ]]; then
    REPO_SPEC="${BASH_REMATCH[1]}"; REF="${BASH_REMATCH[2]}"; SUB="${BASH_REMATCH[4]:-}"
  elif [[ "$spec" =~ ^([^/]+/[^/]+)#(.+)$ ]]; then
    REPO_SPEC="${BASH_REMATCH[1]}"; REF="${BASH_REMATCH[2]}"; SUB=""
  elif [[ "$spec" =~ ^([^/]+/[^/]+)(/(.*))?$ ]]; then
    REPO_SPEC="${BASH_REMATCH[1]}"; SUB="${BASH_REMATCH[3]:-}"
  else
    err "无法识别的来源: $SOURCE（支持本地目录或 github.com/owner/repo[/sub]）"
    exit 1
  fi

  if [[ "$REPO_SPEC" != */* ]]; then
    err "GitHub 来源需要 owner/repo 形式"; exit 1
  fi

  ok "克隆 https://github.com/$REPO_SPEC${REF:+ (${REF})} ..."
  if ! clone_repo "$REPO_SPEC" "$REF" "$TMP_DIR/repo"; then
    err "克隆失败（git 与 tarball 均失败，请检查网络）"
    exit 1
  fi

  SRC_DIR="$TMP_DIR/repo${SUB:+/$SUB}"
  [[ -d "$SRC_DIR" ]] || { err "仓库内目录不存在: $SUB"; exit 1; }
fi

# ─────────── 确定名称并拷贝 ───────────
NAME="${NAME:-$(basename "$SRC_DIR")}"
if [[ ! "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  err "技能名只能包含字母/数字/_/-（当前: $NAME；可用 --name 指定）"; exit 1
fi

TARGET="$SKILLS_DIR/$NAME"
if [[ -e "$TARGET" ]] && (( ! FORCE )); then
  err "已存在: skills/$NAME（用 --force 覆盖）"; exit 1
fi

mkdir -p "$SKILLS_DIR"
rm -rf "$TARGET"
( cd "$SRC_DIR" && tar cf - --exclude='.git' --exclude='.github' . ) \
  | ( mkdir -p "$TARGET" && tar xf - -C "$TARGET" )
ok "已拷贝 → skills/$NAME"

# ─────────── 校验 SKILL.md ───────────
if ! node -e '
  const fs = require("fs");
  const dir = process.argv[1];
  const f = dir + "/SKILL.md";
  if (!fs.existsSync(f)) { console.error("缺少 SKILL.md: " + f); process.exit(1); }
  const s = fs.readFileSync(f, "utf8");
  const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(s);
  if (!m) { console.error("SKILL.md 缺少 YAML frontmatter"); process.exit(1); }
  const fm = m[1];
  const nm = /(?:^|\n)name:\s*["\x27]?([A-Za-z0-9_-]+)/.exec(fm);
  if (!nm) { console.error("frontmatter 缺少 name"); process.exit(1); }
  if (nm[1] !== process.argv[2]) { console.error(`frontmatter name(${nm[1]}) 与目录名(${process.argv[2]})不一致`); process.exit(1); }
  if (!/(?:^|\n)description:\s*\S/.test(fm)) { console.error("frontmatter 缺少 description"); process.exit(1); }
  console.log("frontmatter 合法: name=" + nm[1]);
' "$TARGET" "$NAME"; then
  err "SKILL.md 校验未通过 —— 正确格式:"
  printf '  ---\n  name: %s\n  description: 一句话说明用途\n  ---\n  正文…\n' "$NAME"
  rm -rf "$TARGET"
  ok "已回滚删除 skills/$NAME"
  exit 1
fi
ok "SKILL.md 校验通过"

# ─────────── 提交（--commit）───────────
if (( COMMIT )); then
  ( cd "$REPO_DIR" && git add "skills/$NAME" && git commit --quiet -m "添加 skill: $NAME" )
  ok "已提交: $NAME"
fi

printf '\n%s 完成\n' "$GREEN✓$RESET"
printf '  %s添加即生效（settings.json 已指向 skills/ 目录）；git push 后其他主机 git pull 即可。%s\n' "$DIM" "$RESET"
if (( ! COMMIT )); then
  printf '  %s提示: 可用 --commit 自动提交，或手动 git add -A && git commit%s\n' "$DIM" "$RESET"
fi