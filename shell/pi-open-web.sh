# ═══ pi-config: pi → 打开 Web UI（本块由 install.sh 管理，请勿手改）═══
# 输入 pi（不带参数）→ 打开 pi-web-ui 浏览器界面
# 输入 pi "提问" / pi --print ... → 仍走终端 TUI（保留原功能）
# 输入 pi-tui / \pi → 强制终端 TUI
_pi_open_web() {
  local url="${PI_WEB_URL:-http://127.0.0.1:8787}"

  # 1) 确保 pi-web-ui 服务在运行（优先 systemd，失败则临时拉起）
  if ! curl -sf "$url/api/health" >/dev/null 2>&1; then
    systemctl --user start pi-web-ui >/dev/null 2>&1 \
      || { nohup pi-web-ui --no-browser >/dev/null 2>&1 & }
    local i
    for i in $(seq 1 15); do
      curl -sf "$url/api/health" >/dev/null 2>&1 && break
      sleep 1
    done
  fi

  # 2) 有图形环境 → 打开浏览器；无图形（SSH 等）→ 打印地址
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    command xdg-open "$url" >/dev/null 2>&1 \
      || command sensible-browser "$url" >/dev/null 2>&1 \
      || echo "pi-web-ui 已运行，请手动打开: $url"
  else
    echo "pi-web-ui 已运行: $url"
  fi
}

pi() {
  if [[ $# -eq 0 ]]; then
    _pi_open_web
  else
    command pi "$@"
  fi
}
alias pi-tui='command pi'
# ═══ pi-config: end ═══