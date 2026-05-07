@echo off
chcp 65001 >nul 2>&1
title Meeting Notes App

echo.
echo ================================================
echo   Meeting Notes APP  (Local Privacy Edition)
echo ================================================
echo.

REM ─── 1. Find Python ───────────────────────────────
set PYTHON_CMD=
python --version >nul 2>&1
if not errorlevel 1 set PYTHON_CMD=python
if "%PYTHON_CMD%"=="" (
    py --version >nul 2>&1
    if not errorlevel 1 set PYTHON_CMD=py
)
if "%PYTHON_CMD%"=="" (
    echo [ERROR] Python not found!
    echo        Install: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

REM ─── 2. Check .venv state ─────────────────────────
set VENV_DIR=%~dp0.venv
set VENV_PYTHON=%VENV_DIR%\Scripts\python.exe
set VENV_PIP=%VENV_DIR%\Scripts\pip.exe

REM Case A: .venv doesn't exist at all
if not exist "%VENV_PYTHON%" goto :build_venv

REM Case B: python.exe exists but is broken (base Python moved/uninstalled)
"%VENV_PYTHON%" --version >nul 2>&1
if errorlevel 1 (
    echo   [!!] .venv is broken, rebuilding...
    rmdir /s /q "%VENV_DIR%"
    goto :build_venv
)

REM Case C: python.exe works but packages were never installed
"%VENV_PYTHON%" -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 (
    echo   [!!] Packages missing, installing now...
    goto :install_pkgs
)

REM All good — skip to start
goto :start_server

REM ─── Build fresh .venv ────────────────────────────
:build_venv
echo   Creating .venv...
%PYTHON_CMD% -m venv "%VENV_DIR%"
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to create .venv
    echo.
    pause
    exit /b 1
)
echo   Upgrading pip...
"%VENV_PIP%" install --upgrade pip --quiet

REM (fall through to install_pkgs)

REM ─── Install packages ─────────────────────────────
:install_pkgs
echo.
echo   Installing packages — this may take several minutes...
echo.

nvidia-smi >nul 2>&1
if not errorlevel 1 (
    echo   [OK] NVIDIA GPU detected — installing PyTorch CUDA...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cu121
) else (
    echo   [--] No GPU — installing PyTorch CPU version...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 (
    echo.
    echo [ERROR] PyTorch install failed. Check internet and try again.
    echo.
    pause
    exit /b 1
)

echo   Installing fastapi / uvicorn / faster-whisper...
"%VENV_PIP%" install fastapi "uvicorn[standard]" python-multipart faster-whisper
if errorlevel 1 (
    echo.
    echo [ERROR] Package install failed. Check internet and try again.
    echo.
    pause
    exit /b 1
)

REM Verify packages after install
"%VENV_PYTHON%" -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Packages still missing. Try running install.bat for a clean reinstall.
    echo.
    pause
    exit /b 1
)
echo.
echo   [OK] All packages ready!
echo.

REM ─── Start server ─────────────────────────────────
:start_server
if not exist "%~dp0server.py" (
    echo.
    echo [ERROR] server.py not found.
    echo.
    pause
    exit /b 1
)

echo   [OK] Environment ready
echo.
echo   Starting server...
echo   (First run downloads the Whisper model — may take a few minutes)
echo.
echo   Browser will open automatically when ready.
echo   Or visit: http://localhost:8000
echo.
echo ------------------------------------------------
echo   Close this window to stop the server
echo ------------------------------------------------
echo.

start /b powershell -WindowStyle Hidden -NonInteractive -Command "$i=0; while($i -lt 60){ Start-Sleep 3; try{ $r=Invoke-WebRequest 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop; if($r.StatusCode -eq 200){ Start-Process 'http://localhost:8000'; break } }catch{}; $i++ }"

cd /d "%~dp0"
"%VENV_PYTHON%" server.py

echo.
echo Server stopped.
pause
