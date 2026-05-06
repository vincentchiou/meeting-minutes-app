@echo off
chcp 65001 >nul 2>&1
title Meeting Notes App

echo.
echo ================================================
echo   Meeting Notes APP  (Local Privacy Edition)
echo ================================================
echo.

set VENV_PYTHON=%~dp0.venv\Scripts\python.exe
if not exist "%VENV_PYTHON%" (
    echo.
    echo [ERROR] .venv not found. Please run install.bat first.
    echo.
    pause
    exit /b 1
)

"%VENV_PYTHON%" -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Packages missing. Please run install.bat again.
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

echo   [OK] Environment check passed
echo.
echo   Starting server... (first run will download Whisper model)
echo.
echo   Browser will open automatically when ready.
echo   Or go to: http://localhost:8000
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
