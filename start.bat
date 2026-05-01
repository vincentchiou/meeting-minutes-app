@echo off
chcp 65001 >nul
title 錄音轉會議紀錄（本地版）

echo.
echo ╔══════════════════════════════════════════════╗
echo ║      錄音轉會議紀錄 APP（本地 GPU 版）        ║
echo ╚══════════════════════════════════════════════╝
echo.
echo  啟動中，請稍候...
echo  首次啟動需下載 Whisper 模型，可能需要數分鐘。
echo.
echo  伺服器就緒後，請開啟瀏覽器前往：
echo  ▶  http://localhost:8000
echo.
echo  關閉此視窗即停止伺服器。
echo ────────────────────────────────────────────────
echo.

REM 檢查 Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ 找不到 Python，請先執行 install.bat
    pause
    exit /b 1
)

REM 檢查 server.py
if not exist "%~dp0server.py" (
    echo ❌ 找不到 server.py，請確認檔案完整
    pause
    exit /b 1
)

REM 自動開啟瀏覽器（等待 3 秒讓伺服器啟動）
start /min "" cmd /c "timeout /t 4 >nul && start http://localhost:8000"

REM 啟動 FastAPI 伺服器
cd /d "%~dp0"
python server.py

echo.
echo 伺服器已停止。
pause
