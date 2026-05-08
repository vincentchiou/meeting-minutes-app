@echo off
chcp 65001 >nul 2>&1
title Meeting Notes APP
powershell -NoProfile -Command "[console]::Title = ([char]0x9304+[char]0x97f3+[char]0x8f49+[char]0x6703+[char]0x8b70+[char]0x7d00+[char]0x9304+[char]0x0020+[char]0x0041+[char]0x0050+[char]0x0050)"

powershell -NoProfile -Command "Write-Host"
echo ================================================
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x9304+[char]0x97f3+[char]0x8f49+[char]0x6703+[char]0x8b70+[char]0x7d00+[char]0x9304+[char]0x0020+[char]0x0041+[char]0x0050+[char]0x0050+[char]0x0020+[char]0x0020+[char]0x0028+[char]0x672c+[char]0x5730+[char]0x96b1+[char]0x79c1+[char]0x7248+[char]0x0029) -ForegroundColor Cyan"
echo ================================================
powershell -NoProfile -Command "Write-Host"

REM --- 1. Find Python ---
set PYTHON_CMD=
python --version >nul 2>&1
if not errorlevel 1 set PYTHON_CMD=python
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Python\pythoncore-3.13-64\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Python\pythoncore-3.13-64\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python314\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python314\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python313\python.exe
if "%PYTHON_CMD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe

if "%PYTHON_CMD%"=="" goto :install_python

for /f "tokens=2" %%v in ('%PYTHON_CMD% --version 2^>^&1') do powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+'%%v') -ForegroundColor Green"

REM --- 2. Find Python 3.12 (required for PyTorch) ---
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x6aa2+[char]0x67e5+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0x0020+[char]0x0028+[char]0x0050+[char]0x0079+[char]0x0054+[char]0x006f+[char]0x0072+[char]0x0063+[char]0x0068+[char]0x0020+[char]0x9700+[char]0x8981+[char]0x0029+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Gray"
set VENV_BUILD=
if exist "%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe
if "%VENV_BUILD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%VENV_BUILD%"=="" if exist "C:\Python312\python.exe" set VENV_BUILD=C:\Python312\python.exe

if not "%VENV_BUILD%"=="" goto :venv_check

REM Python 3.12 not found, auto-install
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0021+[char]0x0021+[char]0x0020+[char]0x0020+[char]0x627e+[char]0x4e0d+[char]0x5230+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0xff0c+[char]0x900f+[char]0x904e+[char]0x0020+[char]0x0077+[char]0x0069+[char]0x006e+[char]0x0067+[char]0x0065+[char]0x0074+[char]0x0020+[char]0x81ea+[char]0x52d5+[char]0x5b89+[char]0x88dd+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0028+[char]0x0050+[char]0x0079+[char]0x0054+[char]0x006f+[char]0x0072+[char]0x0063+[char]0x0068+[char]0x0020+[char]0x5c1a+[char]0x4e0d+[char]0x652f+[char]0x63f4+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0033+[char]0x0020+[char]0x002f+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0034+[char]0x0029) -ForegroundColor Gray"
powershell -NoProfile -Command "Write-Host"
winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto :no_py312

REM Confirm after install
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%VENV_BUILD%"=="" goto :no_py312

powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0x0020+[char]0x5c31+[char]0x7dd2) -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host"

REM --- 3. Check .venv status ---
:venv_check
set VENV_DIR=%~dp0.venv
set VENV_PYTHON=%VENV_DIR%\Scripts\python.exe
set VENV_PIP=%VENV_DIR%\Scripts\pip.exe

if not exist "%VENV_PYTHON%" goto :build_venv

REM Confirm .venv uses Python 3.12
for /f "tokens=2" %%v in ('"%VENV_PYTHON%" --version 2^>^&1') do set VENV_VER=%%v
echo %VENV_VER% | findstr /b "3.12" >nul 2>&1
if errorlevel 1 (
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0021+[char]0x0021+[char]0x0020+[char]0x0020+[char]0x002e+[char]0x0076+[char]0x0065+[char]0x006e+[char]0x0076+[char]0x0020+[char]0x7248+[char]0x672c+[char]0x4e0d+[char]0x662f+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0xff0c+[char]0x91cd+[char]0x65b0+[char]0x5efa+[char]0x7acb+[char]0x4e2d+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Yellow"
    rmdir /s /q "%VENV_DIR%"
    goto :build_venv
)

"%VENV_PYTHON%" --version >nul 2>&1
if errorlevel 1 goto :rebuild_venv

"%VENV_PIP%" --version >nul 2>&1
if errorlevel 1 goto :rebuild_venv

"%VENV_PYTHON%" -c "import fastapi, uvicorn, faster_whisper" >nul 2>&1
if errorlevel 1 goto :install_pkgs

goto :ffmpeg_check

:rebuild_venv
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0021+[char]0x0021+[char]0x0020+[char]0x0020+[char]0x002e+[char]0x0076+[char]0x0065+[char]0x006e+[char]0x0076+[char]0x0020+[char]0x640d+[char]0x58de+[char]0xff0c+[char]0x91cd+[char]0x65b0+[char]0x5efa+[char]0x7acb+[char]0x4e2d+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Yellow"
rmdir /s /q "%VENV_DIR%"

:build_venv
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x5efa+[char]0x7acb+[char]0x0020+[char]0x002e+[char]0x0076+[char]0x0065+[char]0x006e+[char]0x0076+[char]0x0020+[char]0x0028+[char]0x4f7f+[char]0x7528+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0x0029+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Gray"
"%VENV_BUILD%" -m venv "%VENV_DIR%"
if errorlevel 1 goto :venv_fail
"%VENV_PIP%" install --upgrade pip --quiet 2>nul

:install_pkgs
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x5b89+[char]0x88dd+[char]0x5957+[char]0x4ef6+[char]0x4e2d+[char]0x0020+[char]0x0028+[char]0x9996+[char]0x6b21+[char]0x5b89+[char]0x88dd+[char]0x9700+[char]0x8981+[char]0x6578+[char]0x5206+[char]0x9418+[char]0xff0c+[char]0x8acb+[char]0x8010+[char]0x5fc3+[char]0x7b49+[char]0x5019+[char]0x0029+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Cyan"
powershell -NoProfile -Command "Write-Host"
nvidia-smi >nul 2>&1
if not errorlevel 1 (
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x5075+[char]0x6e2c+[char]0x5230+[char]0x0020+[char]0x0047+[char]0x0050+[char]0x0055+[char]0xff0c+[char]0x5b89+[char]0x88dd+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0054+[char]0x006f+[char]0x0072+[char]0x0063+[char]0x0068+[char]0x0020+[char]0x0043+[char]0x0055+[char]0x0044+[char]0x0041+[char]0x0020+[char]0x7248+[char]0x672c+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Green"
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cu121
) else (
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x002d+[char]0x002d+[char]0x005d+[char]0x0020+[char]0x672a+[char]0x5075+[char]0x6e2c+[char]0x5230+[char]0x0020+[char]0x0047+[char]0x0050+[char]0x0055+[char]0xff0c+[char]0x5b89+[char]0x88dd+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0054+[char]0x006f+[char]0x0072+[char]0x0063+[char]0x0068+[char]0x0020+[char]0x0043+[char]0x0050+[char]0x0055+[char]0x0020+[char]0x7248+[char]0x672c+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Gray"
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 goto :pkg_fail

echo   Installing fastapi / uvicorn / faster-whisper...
"%VENV_PIP%" install fastapi "uvicorn[standard]" python-multipart faster-whisper
if errorlevel 1 goto :pkg_fail

powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x6240+[char]0x6709+[char]0x5957+[char]0x4ef6+[char]0x5b89+[char]0x88dd+[char]0x5b8c+[char]0x6210+[char]0xff01) -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host"

REM --- 4. Check ffmpeg ---
:ffmpeg_check
ffmpeg -version >nul 2>&1
if not errorlevel 1 goto :start_server

powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0021+[char]0x0021+[char]0x0020+[char]0x0020+[char]0x627e+[char]0x4e0d+[char]0x5230+[char]0x0020+[char]0x0066+[char]0x0066+[char]0x006d+[char]0x0070+[char]0x0065+[char]0x0067+[char]0xff0c+[char]0x900f+[char]0x904e+[char]0x0020+[char]0x0077+[char]0x0069+[char]0x006e+[char]0x0067+[char]0x0065+[char]0x0074+[char]0x0020+[char]0x81ea+[char]0x52d5+[char]0x5b89+[char]0x88dd+[char]0x4e2d+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0028+[char]0x006d+[char]0x0070+[char]0x0033+[char]0x002c+[char]0x0020+[char]0x006d+[char]0x0034+[char]0x0061+[char]0x002c+[char]0x0020+[char]0x006f+[char]0x0067+[char]0x0067+[char]0x0020+[char]0x7b49+[char]0x683c+[char]0x5f0f+[char]0x9700+[char]0x8981+[char]0x0020+[char]0x0066+[char]0x0066+[char]0x006d+[char]0x0070+[char]0x0065+[char]0x0067+[char]0x0029) -ForegroundColor Gray"
winget install Gyan.FFmpeg -e --silent --accept-package-agreements --accept-source-agreements >nul 2>&1

REM Confirm after install
ffmpeg -version >nul 2>&1
if not errorlevel 1 (
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x0066+[char]0x0066+[char]0x006d+[char]0x0070+[char]0x0065+[char]0x0067+[char]0x0020+[char]0x5b89+[char]0x88dd+[char]0x5b8c+[char]0x6210) -ForegroundColor Green"
    goto :start_server
)

if exist "C:\Program Files\ffmpeg\bin\ffmpeg.exe" (
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x0066+[char]0x0066+[char]0x006d+[char]0x0070+[char]0x0065+[char]0x0067+[char]0x0020+[char]0x5c31+[char]0x7dd2) -ForegroundColor Green"
    goto :start_server
)

powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x002d+[char]0x002d+[char]0x005d+[char]0x0020+[char]0x0066+[char]0x0066+[char]0x006d+[char]0x0070+[char]0x0065+[char]0x0067+[char]0x0020+[char]0x53ef+[char]0x80fd+[char]0x9700+[char]0x8981+[char]0x91cd+[char]0x65b0+[char]0x555f+[char]0x52d5+[char]0x5f8c+[char]0x751f+[char]0x6548) -ForegroundColor Yellow"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0028+[char]0x0077+[char]0x0061+[char]0x0076+[char]0x0020+[char]0x002f+[char]0x0020+[char]0x0077+[char]0x0065+[char]0x0062+[char]0x006d+[char]0x0020+[char]0x683c+[char]0x5f0f+[char]0x7121+[char]0x9700+[char]0x0020+[char]0x0066+[char]0x0066+[char]0x006d+[char]0x0070+[char]0x0065+[char]0x0067+[char]0x0020+[char]0x4ecd+[char]0x53ef+[char]0x4f7f+[char]0x7528+[char]0x0029) -ForegroundColor Gray"

:start_server
if not exist "%~dp0server.py" goto :no_server

powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x74b0+[char]0x5883+[char]0x5c31+[char]0x7dd2) -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x555f+[char]0x52d5+[char]0x4f3a+[char]0x670d+[char]0x5668+[char]0x4e2d+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Cyan"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0028+[char]0x9996+[char]0x6b21+[char]0x57f7+[char]0x884c+[char]0x6703+[char]0x4e0b+[char]0x8f09+[char]0x0020+[char]0x0057+[char]0x0068+[char]0x0069+[char]0x0073+[char]0x0070+[char]0x0065+[char]0x0072+[char]0x0020+[char]0x8a9e+[char]0x97f3+[char]0x6a21+[char]0x578b+[char]0xff0c+[char]0x9700+[char]0x8981+[char]0x6578+[char]0x5206+[char]0x9418+[char]0x0029) -ForegroundColor Gray"
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x700f+[char]0x89bd+[char]0x5668+[char]0x5c07+[char]0x81ea+[char]0x52d5+[char]0x958b+[char]0x555f+[char]0x3002+[char]0x6216+[char]0x624b+[char]0x52d5+[char]0x524d+[char]0x5f80+[char]0xff1a+[char]0x0068+[char]0x0074+[char]0x0074+[char]0x0070+[char]0x003a+[char]0x002f+[char]0x002f+[char]0x006c+[char]0x006f+[char]0x0063+[char]0x0061+[char]0x006c+[char]0x0068+[char]0x006f+[char]0x0073+[char]0x0074+[char]0x003a+[char]0x0038+[char]0x0030+[char]0x0030+[char]0x0030) -ForegroundColor White"
powershell -NoProfile -Command "Write-Host"
echo ------------------------------------------------
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x95dc+[char]0x9589+[char]0x6b64+[char]0x8996+[char]0x7a97+[char]0x5373+[char]0x53ef+[char]0x505c+[char]0x6b62+[char]0x4f3a+[char]0x670d+[char]0x5668) -ForegroundColor Yellow"
echo ------------------------------------------------
powershell -NoProfile -Command "Write-Host"

start /b powershell -WindowStyle Hidden -NonInteractive -Command "$i=0; while($i -lt 300){ Start-Sleep 3; try{ $r=Invoke-WebRequest 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop; if($r.StatusCode -eq 200){ Start-Process 'http://localhost:8000'; break } }catch{}; $i++ }"

cd /d "%~dp0"
"%VENV_PYTHON%" server.py

powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x4f3a+[char]0x670d+[char]0x5668+[char]0x5df2+[char]0x505c+[char]0x6b62+[char]0x3002) -ForegroundColor Gray"
goto :end

REM --- Error handlers ---
:install_python
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0021+[char]0x0021+[char]0x0020+[char]0x0020+[char]0x627e+[char]0x4e0d+[char]0x5230+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0xff0c+[char]0x81ea+[char]0x52d5+[char]0x5b89+[char]0x88dd+[char]0x4e2d+[char]0x002e+[char]0x002e+[char]0x002e) -ForegroundColor Yellow"
winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto :python_fail
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%PYTHON_CMD%"=="" goto :python_restart
goto :venv_check

:python_fail
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x005b+[char]0x932f+[char]0x8aa4+[char]0x005d+[char]0x0020+[char]0x81ea+[char]0x52d5+[char]0x5b89+[char]0x88dd+[char]0x5931+[char]0x6557+[char]0x3002) -ForegroundColor Red"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x8acb+[char]0x624b+[char]0x52d5+[char]0x5b89+[char]0x88dd+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0xff1a) -ForegroundColor Red"
echo        https://www.python.org/downloads/release/python-3129/
goto :end

:python_restart
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x005b+[char]0x004f+[char]0x004b+[char]0x005d+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0x0020+[char]0x5b89+[char]0x88dd+[char]0x5b8c+[char]0x6210+[char]0xff01+[char]0x8acb+[char]0x95dc+[char]0x9589+[char]0x6b64+[char]0x8996+[char]0x7a97+[char]0x5f8c+[char]0x518d+[char]0x6b21+[char]0x57f7+[char]0x884c+[char]0x0020+[char]0x0073+[char]0x0074+[char]0x0061+[char]0x0072+[char]0x0074+[char]0x002e+[char]0x0062+[char]0x0061+[char]0x0074+[char]0x3002) -ForegroundColor Green"
goto :end

:no_py312
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x005b+[char]0x932f+[char]0x8aa4+[char]0x005d+[char]0x0020+[char]0x7121+[char]0x6cd5+[char]0x5b89+[char]0x88dd+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0x3002) -ForegroundColor Red"
powershell -NoProfile -Command "Write-Host ([char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0054+[char]0x006f+[char]0x0072+[char]0x0063+[char]0x0068+[char]0x0020+[char]0x9700+[char]0x8981+[char]0x0020+[char]0x0050+[char]0x0079+[char]0x0074+[char]0x0068+[char]0x006f+[char]0x006e+[char]0x0020+[char]0x0033+[char]0x002e+[char]0x0031+[char]0x0032+[char]0x0020+[char]0x4ee5+[char]0x4e0b+[char]0x7248+[char]0x672c+[char]0x3002) -ForegroundColor Red"
echo        https://www.python.org/downloads/release/python-3129/
goto :end

:venv_fail
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x005b+[char]0x932f+[char]0x8aa4+[char]0x005d+[char]0x0020+[char]0x5efa+[char]0x7acb+[char]0x0020+[char]0x002e+[char]0x0076+[char]0x0065+[char]0x006e+[char]0x0076+[char]0x0020+[char]0x5931+[char]0x6557+[char]0x3002+[char]0x8acb+[char]0x5617+[char]0x8a66+[char]0x4ee5+[char]0x7cfb+[char]0x7d71+[char]0x7ba1+[char]0x7406+[char]0x54e1+[char]0x8eab+[char]0x4efd+[char]0x57f7+[char]0x884c+[char]0x3002) -ForegroundColor Red"
goto :end

:pkg_fail
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x005b+[char]0x932f+[char]0x8aa4+[char]0x005d+[char]0x0020+[char]0x5957+[char]0x4ef6+[char]0x5b89+[char]0x88dd+[char]0x5931+[char]0x6557+[char]0x3002+[char]0x8acb+[char]0x78ba+[char]0x8a8d+[char]0x7db2+[char]0x8def+[char]0x9023+[char]0x7dda+[char]0x5f8c+[char]0x518d+[char]0x8a66+[char]0x3002) -ForegroundColor Red"
goto :end

:no_server
powershell -NoProfile -Command "Write-Host"
powershell -NoProfile -Command "Write-Host ([char]0x005b+[char]0x932f+[char]0x8aa4+[char]0x005d+[char]0x0020+[char]0x627e+[char]0x4e0d+[char]0x5230+[char]0x0020+[char]0x0073+[char]0x0065+[char]0x0072+[char]0x0076+[char]0x0065+[char]0x0072+[char]0x002e+[char]0x0070+[char]0x0079+[char]0xff0c+[char]0x8acb+[char]0x91cd+[char]0x65b0+[char]0x4e0b+[char]0x8f09+[char]0x672c+[char]0x7a0b+[char]0x5f0f+[char]0x3002) -ForegroundColor Red"
goto :end

:end
powershell -NoProfile -Command "Write-Host"
pause
