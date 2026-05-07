@echo off
chcp 65001 >nul 2>&1
title Meeting Notes App

echo.
echo ================================================
echo   Meeting Notes APP  (Local Privacy Edition)
echo ================================================
echo.

REM --- 1. Find Python ---
set PYTHON_CMD=
python --version >nul 2>&1
if not errorlevel 1 set PYTHON_CMD=python

REM Fallback: check common install locations (no py.exe launcher)
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Python\pythoncore-3.13-64\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Python\pythoncore-3.13-64\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python314\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python313\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%PYTHON_CMD%"=="" if exist "C:\Python314\python.exe" set PYTHON_CMD=C:\Python314\python.exe
if "%PYTHON_CMD%"=="" if exist "C:\Python313\python.exe" set PYTHON_CMD=C:\Python313\python.exe
if "%PYTHON_CMD%"=="" if exist "C:\Python312\python.exe" set PYTHON_CMD=C:\Python312\python.exe

if not "%PYTHON_CMD%"=="" goto :python_ok

REM Python not found -- try winget auto-install
echo   [!!] Python not found -- installing automatically...
echo        (requires internet, ~25 MB, please wait)
echo.
winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto :python_fail

REM Re-check after winget
python --version >nul 2>&1
if not errorlevel 1 set PYTHON_CMD=python
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%PYTHON_CMD%"=="" goto :python_restart

:python_ok
for /f "tokens=2" %%v in ('%PYTHON_CMD% --version 2^>^&1') do echo   [OK] Python %%v

REM --- 2. Check .venv state ---
set VENV_DIR=%~dp0.venv
set VENV_PYTHON=%VENV_DIR%\Scripts\python.exe
set VENV_PIP=%VENV_DIR%\Scripts\pip.exe

if not exist "%VENV_PYTHON%" goto :build_venv

"%VENV_PYTHON%" --version >nul 2>&1
if errorlevel 1 goto :rebuild_venv

"%VENV_PIP%" --version >nul 2>&1
if errorlevel 1 goto :rebuild_venv

"%VENV_PYTHON%" -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 goto :install_pkgs

goto :start_server

:rebuild_venv
echo   [!!] .venv is broken -- rebuilding...
rmdir /s /q "%VENV_DIR%"

:build_venv
echo   Creating .venv...
"%PYTHON_CMD%" -m venv "%VENV_DIR%"
if errorlevel 1 goto :venv_fail
echo   Upgrading pip...
"%VENV_PIP%" install --upgrade pip --quiet

:install_pkgs
echo.
echo   Installing packages (first time takes several minutes)...
echo.
nvidia-smi >nul 2>&1
if not errorlevel 1 (
    echo   [OK] GPU detected -- PyTorch CUDA...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cu121
) else (
    echo   [--] No GPU -- PyTorch CPU...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 goto :pkg_fail

echo   Installing fastapi / uvicorn / faster-whisper...
"%VENV_PIP%" install fastapi "uvicorn[standard]" python-multipart faster-whisper
if errorlevel 1 goto :pkg_fail

echo.
echo   [OK] All packages ready!
echo.

:start_server
if not exist "%~dp0server.py" goto :no_server

echo   [OK] Environment ready
echo.
echo   Starting server...
echo   (First run downloads Whisper model -- may take a few minutes)
echo.
echo   Browser will open automatically. Or visit: http://localhost:8000
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
goto :end

:python_fail
echo.
echo [ERROR] Auto-install failed.
echo        Please install Python manually:
echo        https://www.python.org/downloads/
echo        (Check "Add Python to PATH" during install)
goto :end

:python_restart
echo.
echo [OK] Python installed! Please close this window and run start.bat again.
goto :end

:venv_fail
echo.
echo [ERROR] Failed to create .venv
echo        Try running as Administrator, or check disk space.
goto :end

:pkg_fail
echo.
echo [ERROR] Package install failed. Check internet and try again.
goto :end

:no_server
echo.
echo [ERROR] server.py not found. Please re-download the app.
goto :end

:end
echo.
pause
