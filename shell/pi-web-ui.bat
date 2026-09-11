@echo off
rem pi-web-ui 批处理启动脚本
rem 用法: pi-web-ui 或 pi-web-ui --no-browser
rem 默认端口: 8787

rem 确保 pi-web-ui 命令可用
where pi-web-ui >nul 2>&1 || (
    echo.
    echo pi-web-ui 命令未找到，请先运行: npm i -g pi-web-ui
    pause
    exit /b 1
)

rem 启动 pi-web-ui，传递所有参数
pi-web-ui %*

rem 启动后保持终端打开（可选）
rem echo.
rem echo pi-web-ui 运行中，访问 http://127.0.0.1:8787
rem echo 按 Ctrl+C 停止服务...
rem timeout /t 1 >nul