@echo off
chcp 65001 >nul
title 錄音轉會議紀錄（本地版）

echo.
echo ╔══════════════════════════════════════════════╗
echo ║      錄音轉會議紀錄 APP（本地隱私·算力版）   ║
echo ╚══════════════════════════════════════════════╝
echo.

REM ── 檢查 Python ──
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ 找不到 Python！請先執行 install.bat
    pause & exit /b 1
)

REM ── 檢查套件是否安裝 ──
python -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 (
    echo.
    echo ❌ 必要套件尚未安裝！
    echo    請先執行 install.bat 再重新啟動。
    echo.
    pause & exit /b 1
)

REM ── 檢查 server.py ──
if not exist "%~dp0server.py" (
    echo ❌ 找不到 server.py，請確認檔案完整
    pause & exit /b 1
)

echo  ✅ 環境檢查通過
echo.
echo  正在啟動伺服器，請稍候…
echo  （首次啟動需下載 Whisper 模型，可能需數分鐘）
echo.
echo  伺服器就緒後瀏覽器會自動開啟，
echo  或手動前往：http://localhost:8000
echo.
echo ────────────────────────────────────────────────
echo  關閉此視窗即停止伺服器
echo ────────────────────────────────────────────────
echo.

REM ── 在背景等候伺服器就緒後再開瀏覽器 ──
REM  輪詢 /health（每 3 秒試一次，最多等 3 分鐘）
start /min "" cmd /c ^
  "for /L %%i in (1,1,60) do (^
    timeout /t 3 >nul & ^
    curl -sf http://localhost:8000/health >nul 2>&1 && ^
    (start http://localhost:8000 & exit) ^
  )"

REM ── 啟動 FastAPI 伺服器 ──
cd /d "%~dp0"
python server.py

echo.
echo 伺服器已停止。
pause
