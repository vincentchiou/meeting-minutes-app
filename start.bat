@echo off
chcp 65001 >nul 2>&1
title 錄音轉會議紀錄（本地版）

echo.
echo ================================================
echo   錄音轉會議紀錄 APP（本地隱私版）
echo ================================================
echo.

REM ── 尋找 Python（優先 python，備用 py launcher）──
set PYTHON_CMD=
python --version >nul 2>&1
if not errorlevel 1 set PYTHON_CMD=python
if "%PYTHON_CMD%"=="" (
    py --version >nul 2>&1
    if not errorlevel 1 set PYTHON_CMD=py
)
if "%PYTHON_CMD%"=="" (
    echo.
    echo [錯誤] 找不到 Python！
    echo        請先執行 install.bat，或至以下網址安裝：
    echo        https://www.python.org/downloads/
    echo        （安裝時請勾選 Add Python to PATH）
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('%PYTHON_CMD% --version 2^>^&1') do echo   使用：%%v

REM ── 檢查必要套件 ──
%PYTHON_CMD% -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 (
    echo.
    echo [錯誤] 必要套件尚未安裝！
    echo        請先執行 install.bat 再重新啟動。
    echo.
    pause
    exit /b 1
)

REM ── 檢查 server.py ──
if not exist "%~dp0server.py" (
    echo.
    echo [錯誤] 找不到 server.py，請確認檔案是否完整。
    echo.
    pause
    exit /b 1
)

echo   [OK] 環境檢查通過
echo.
echo   正在啟動伺服器，請稍候...
echo   （首次啟動需下載 Whisper 模型，可能需數分鐘）
echo.
echo   伺服器就緒後瀏覽器會自動開啟，
echo   或手動前往：http://localhost:8000
echo.
echo ------------------------------------------------
echo   關閉此視窗即停止伺服器
echo ------------------------------------------------
echo.

REM ── 背景輪詢：就緒後自動開瀏覽器（PowerShell，每 3 秒，最多 3 分鐘）──
start /b powershell -WindowStyle Hidden -NonInteractive -Command "$i=0; while($i -lt 60){ Start-Sleep 3; try{ $r=Invoke-WebRequest 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop; if($r.StatusCode -eq 200){ Start-Process 'http://localhost:8000'; break } }catch{}; $i++ }"

REM ── 啟動伺服器（前景，關閉視窗即停止）──
cd /d "%~dp0"
%PYTHON_CMD% server.py

echo.
echo 伺服器已停止。
pause
