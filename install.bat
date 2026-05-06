@echo off
chcp 65001 >nul 2>&1
title Meeting Notes App - Installer

echo.
echo ================================================
echo   Meeting Notes APP - Installer
echo ================================================
echo.

echo [1/4] Checking Python...
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
for /f "tokens=2" %%v in ('%PYTHON_CMD% --version 2^>^&1') do echo   [OK] Python %%v

echo.
echo [2/4] Creating .venv sandbox...
set VENV_DIR=%~dp0.venv
set VENV_PYTHON=%VENV_DIR%\Scripts\python.exe
set VENV_PIP=%VENV_DIR%\Scripts\pip.exe

if exist "%VENV_PYTHON%" (
    echo   [OK] .venv already exists
) else (
    %PYTHON_CMD% -m venv "%VENV_DIR%"
    if errorlevel 1 (
        echo.
        echo [ERROR] Failed to create .venv
        echo.
        pause
        exit /b 1
    )
    echo   [OK] .venv created
)

echo   Upgrading pip...
"%VENV_PIP%" install --upgrade pip
echo   [OK] pip ready

echo.
echo [3/4] Installing packages (downloading ~2GB, please wait)...
echo.
nvidia-smi >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%g in ('nvidia-smi --query-gpu=name --format=csv,noheader 2^>nul') do echo   [OK] GPU: %%g
    echo   Installing PyTorch CUDA...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cu121
) else (
    echo   [--] No GPU, installing CPU version...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 (
    echo.
    echo [ERROR] PyTorch install failed. Check internet and retry.
    echo.
    pause
    exit /b 1
)
echo   [OK] PyTorch done

echo   Installing fastapi / uvicorn / faster-whisper...
"%VENV_PIP%" install fastapi "uvicorn[standard]" python-multipart faster-whisper
if errorlevel 1 (
    echo.
    echo [ERROR] Package install failed. Check internet and retry.
    echo.
    pause
    exit /b 1
)
echo   [OK] All packages done

echo.
echo [4/4] Checking ffmpeg...
where ffmpeg >nul 2>&1
if not errorlevel 1 (
    echo   [OK] ffmpeg found
) else (
    echo   [--] ffmpeg not found (wav only)
    echo        Optional: https://ffmpeg.org/download.html
)

echo.
echo ================================================
echo   [OK] Installation complete!
echo   Next step: run start.bat
echo ================================================
echo.
pause
