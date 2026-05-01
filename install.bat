@echo off
chcp 65001 >nul
title 錄音轉會議紀錄 — 安裝程式

echo.
echo ╔══════════════════════════════════════════════╗
echo ║   錄音轉會議紀錄 APP（本地版）安裝程式        ║
echo ║   自動偵測您的電腦環境並安裝適合的套件        ║
echo ╚══════════════════════════════════════════════╝
echo.

REM ────────────────────────────────────────
REM 1. 檢查 Python
REM ────────────────────────────────────────
echo [1/4] 檢查 Python 版本...
python --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo ❌ 未偵測到 Python！
    echo    請先安裝 Python 3.10 以上版本：
    echo    https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set PY_VER=%%v
echo    ✅ Python %PY_VER% 已安裝

REM ────────────────────────────────────────
REM 2. 偵測 NVIDIA GPU / CUDA
REM ────────────────────────────────────────
echo.
echo [2/4] 偵測 NVIDIA 顯卡...
set HAS_GPU=0
nvidia-smi >nul 2>&1
if not errorlevel 1 (
    set HAS_GPU=1
    for /f "tokens=*" %%g in ('nvidia-smi --query-gpu=name --format=csv^,noheader 2^>nul') do set GPU_NAME=%%g
    echo    ✅ 偵測到 GPU：%GPU_NAME%
    echo    → 將安裝 CUDA 加速版本（速度更快）
) else (
    echo    ⚠️  未偵測到 NVIDIA 顯卡
    echo    → 將安裝 CPU 版本（速度較慢，但仍可使用）
)

REM ────────────────────────────────────────
REM 3. 安裝 Python 套件
REM ────────────────────────────────────────
echo.
echo [3/4] 安裝 Python 套件...
echo    安裝 fastapi uvicorn python-multipart faster-whisper...
pip install fastapi "uvicorn[standard]" python-multipart faster-whisper --quiet
if errorlevel 1 (
    echo ❌ 套件安裝失敗，請確認網路連線後重試
    pause
    exit /b 1
)

REM 依 GPU 偵測安裝對應 torch
if "%HAS_GPU%"=="1" (
    echo    安裝 PyTorch CUDA 版（約 2GB，請耐心等候）...
    pip install torch --index-url https://download.pytorch.org/whl/cu121 --quiet
) else (
    echo    安裝 PyTorch CPU 版...
    pip install torch --index-url https://download.pytorch.org/whl/cpu --quiet
)
if errorlevel 1 (
    echo ❌ PyTorch 安裝失敗，請確認網路連線後重試
    pause
    exit /b 1
)
echo    ✅ 套件安裝完成

REM ────────────────────────────────────────
REM 4. 偵測 ffmpeg
REM ────────────────────────────────────────
echo.
echo [4/4] 偵測 ffmpeg...
where ffmpeg >nul 2>&1
if errorlevel 1 (
    echo    ⚠️  未偵測到 ffmpeg
    echo    → 建議安裝以支援 mp3/m4a/ogg 等格式
    echo    → 下載網址：https://ffmpeg.org/download.html
    echo      （下載後解壓縮，將 bin 資料夾加入系統 PATH）
    echo    → 未安裝仍可使用，但僅支援 wav 格式上傳
) else (
    echo    ✅ ffmpeg 已安裝（支援所有音訊格式）
)

REM ────────────────────────────────────────
REM 完成
REM ────────────────────────────────────────
echo.
echo ════════════════════════════════════════════════
echo   ✅ 安裝完成！
echo.
echo   Whisper 語音模型將於第一次執行時自動下載
echo   （依電腦規格約 500MB～3GB，需網路連線）
echo   之後使用完全不需要網路。
echo.
echo   下一步：執行 start.bat 啟動伺服器
echo ════════════════════════════════════════════════
echo.
pause
