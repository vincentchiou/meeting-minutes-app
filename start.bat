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
    echo.
    echo [ERROR] Python not found!
    echo        Install: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

REM ─── 2. Check / create .venv ──────────────────────
set VENV_DIR=%~dp0.venv
set VENV_PYTHON=%VENV_DIR%\Scripts\python.exe
set VENV_PIP=%VENV_DIR%\Scripts\pip.exe

set DO_INSTALL=0
if exist "%VENV_PYTHON%" (
    REM venv exists — verify it actually works
    "%VENV_PYTHON%" --version >nul 2>&1
    if errorlevel 1 (
        echo   [!!] .venv is broken, rebuilding...
        rmdir /s /q "%VENV_DIR%"
        set DO_INSTALL=1
    )
) else (
    set DO_INSTALL=1
)

if "%DO_INSTALL%"=="1" (
    echo   First-time setup — installing packages. This may take several minutes.
    echo.

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

    REM Detect GPU (presence only — avoid nvidia-smi format quirks)
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
    echo   [OK] Setup complete!
    echo.
)

REM ─── 3. Sanity-check packages ─────────────────────
"%VENV_PYTHON%" -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Packages missing even after install.
    echo        Delete the .venv folder and run this script again.
    echo.
    pause
    exit /b 1
)

if not exist "%~dp0server.py" (
    echo.
    echo [ERROR] server.py not found.
    echo.
    pause
    exit /b 1
)

REM ─── 4. Start server ──────────────────────────────
echo   [OK] Environment ready
echo.
echo   Starting server...
echo   (First run will download the Whisper model — may take a few minutes)
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
