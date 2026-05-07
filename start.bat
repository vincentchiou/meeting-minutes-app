@echo off
chcp 65001 >nul 2>&1
title Meeting Notes App

echo.
echo ================================================
echo   Meeting Notes APP  (Local Privacy Edition)
echo ================================================
echo.

REM ─── 1. Find Python; auto-install if missing ─────
call :find_python
if "%PYTHON_CMD%"=="" (
    echo   [!!] Python not found — installing automatically...
    echo        (requires internet, ~25MB, please wait)
    echo.
    winget install --id Python.Python.3.12 -e --silent ^
        --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
        echo.
        echo [ERROR] Auto-install failed.
        echo        Please install Python manually:
        echo        https://www.python.org/downloads/
        echo        (Check "Add Python to PATH" during install)
        echo.
        pause
        exit /b 1
    )
    REM After winget, py launcher is in PATH; try it first
    call :find_python
    REM Fallback: search common install locations
    if "%PYTHON_CMD%"=="" (
        for %%p in (
            "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
            "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
            "%LOCALAPPDATA%\Programs\Python\Python314\python.exe"
            "C:\Python312\python.exe"
            "C:\Python313\python.exe"
        ) do (
            if "%PYTHON_CMD%"=="" (
                if exist %%p set PYTHON_CMD=%%~p
            )
        )
    )
    if "%PYTHON_CMD%"=="" (
        echo.
        echo [ERROR] Python installed but not detected in this session.
        echo        Please close this window and run start.bat again.
        echo.
        pause
        exit /b 1
    )
)
for /f "tokens=2" %%v in ('%PYTHON_CMD% --version 2^>^&1') do echo   [OK] Python %%v

REM ─── 2. Check .venv state (4 cases) ──────────────
set VENV_DIR=%~dp0.venv
set VENV_PYTHON=%VENV_DIR%\Scripts\python.exe
set VENV_PIP=%VENV_DIR%\Scripts\pip.exe

REM Case A: .venv missing entirely
if not exist "%VENV_PYTHON%" goto :build_venv

REM Case B: python.exe broken (base Python uninstalled/moved)
"%VENV_PYTHON%" --version >nul 2>&1
if errorlevel 1 goto :rebuild_venv

REM Case C: pip broken (base Python path changed)
"%VENV_PIP%" --version >nul 2>&1
if errorlevel 1 goto :rebuild_venv

REM Case D: python & pip OK but packages missing
"%VENV_PYTHON%" -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 goto :install_pkgs

goto :start_server

REM ─── Rebuild broken .venv ─────────────────────────
:rebuild_venv
echo   [!!] .venv is broken — rebuilding...
rmdir /s /q "%VENV_DIR%"

REM ─── Build fresh .venv ────────────────────────────
:build_venv
echo   Creating .venv...
"%PYTHON_CMD%" -m venv "%VENV_DIR%"
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
echo   Installing packages — first time may take several minutes...
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

REM ─── Subroutine: find Python in PATH ──────────────
:find_python
set PYTHON_CMD=
python --version >nul 2>&1
if not errorlevel 1 set PYTHON_CMD=python
if "%PYTHON_CMD%"=="" (
    py --version >nul 2>&1
    if not errorlevel 1 set PYTHON_CMD=py
)
exit /b
