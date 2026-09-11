#!/usr/bin/env bash
#
# sync.sh — 一键同步并应用最新配置
#   git pull（若配置了远端）+ 运行 install.sh
#
# 用法:
#   ./sync.sh [install.sh 的附加选项，如 --skip-web-ui / --dry-run]
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }

if git remote -v | grep -q .; then
  echo "${BOLD}▸ git pull${RESET}"
  if git pull --ff-only; then
    ok "已更新到最新"
  else
    warn "git pull 失败（网络/冲突？）。仍会基于本地内容继续安装"
  fi
else
  warn "未配置 git remote —— 跳过 git pull（首次部署可忽略）"
fi

echo
"$REPO_DIR/install.sh" "$@"