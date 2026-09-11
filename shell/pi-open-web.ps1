# ═══ pi-config: PowerShell 版本 → 输入 pi 自动打开 Web UI ═══
# 对应 shell/pi-open-web.sh 的 PowerShell 等效实现
# 将此内容追加到 $PROFILE 或手动执行

function _pi_open_web_ps() {
  $url = "http://127.0.0.1:8787"

  # 1) 确保 pi-web-ui 服务在运行
  if (-not (Test-Url -url $url -Quiet)) {
    # 尝试启动 systemd 用户服务（WSL/Windows 11 用户级系统）
    try {
      $result = systemctl --user start pi-web-ui -ErrorAction Stop 2>$null
      Start-Sleep -Seconds 2
    } catch {
      # systemd 不可用，前台启动 pi-web-ui
      $env:PI_WEB_PORT = "8787"
      $env:PI_WEB_WORKSPACE = "${HOME}"
      $env:PI_WEB_HOST = "127.0.0.1"
      # 后台启动 pi-web-ui（忽略 node-pty 编译警告）
      pi-web-ui --no-browser > $null 2>&1 &
      Start-Sleep -Seconds 3
    }
    # 探测服务就绪
    for ($i = 1; $i -le 15; $i++) {
      if (Test-Url -url $url -Quiet) { break }
      Start-Sleep -Seconds 1
    }
  }

  # 2) 打开浏览器
  try {
    $browser = Get-Content env:BROWSER 2>$null
    if (-not $browser) { $browser = "start" }
    & $browser $url
    Write-Host "pi-web-ui 已运行: $url" -ForegroundColor Green
  } catch {
    Write-Host "pi-web-ui 已运行，请手动打开: $url" -ForegroundColor Yellow
  }
}

# 将 pi 命令追加到当前 PowerShell 配置文件
if (-not (Get-Content $PROFILE -Raw -ErrorAction SilentlyContains "pi-open-web")) {
  Add-Content $PROFILE @"
# pi-config: pi → 打开 Web UI (PowerShell)
function pi() {
    if ($args.Length -eq 0) {
      _pi_open_web_ps
    } else {
      # 传递参数给 pi 命令（此处简化，实际需 pi 二进制}
    }
}
"@
  Write-Host "已将 pi 命令追加到 $PROFILE" -ForegroundColor Cyan
} else {
  Write-Host "pi 命令已存在于 $PROFILE" -ForegroundColor Dim
}