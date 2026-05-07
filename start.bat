@echo off
chcp 65001 >nul 2>&1
title 錄音轉會議紀錄 APP

echo.
echo ================================================
echo   錄音轉會議紀錄 APP  (本地隱私版)
echo ================================================
echo.

REM --- 1. 尋找 Python ---
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

for /f "tokens=2" %%v in ('%PYTHON_CMD% --version 2^>^&1') do echo   [OK] Python %%v

REM --- 2. 尋找 Python 3.12（PyTorch 需要）---
echo   檢查 Python 3.12（PyTorch 需要）...
set VENV_BUILD=
if exist "%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Python\pythoncore-3.12-64\python.exe
if "%VENV_BUILD%"=="" if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%VENV_BUILD%"=="" if exist "C:\Python312\python.exe" set VENV_BUILD=C:\Python312\python.exe

if not "%VENV_BUILD%"=="" goto :venv_check

REM 未找到 Python 3.12，自動安裝
echo   [!!] 找不到 Python 3.12，透過 winget 自動安裝...
echo        （PyTorch 尚不支援 Python 3.13 / 3.14）
echo.
winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto :no_py312

REM 安裝後再次確認
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%VENV_BUILD%"=="" goto :no_py312

echo   [OK] Python 3.12 就緒
echo.

REM --- 3. 檢查 .venv 狀態 ---
:venv_check
set VENV_DIR=%~dp0.venv
set VENV_PYTHON=%VENV_DIR%\Scripts\python.exe
set VENV_PIP=%VENV_DIR%\Scripts\pip.exe

if not exist "%VENV_PYTHON%" goto :build_venv

REM 確認 .venv 使用 Python 3.12
for /f "tokens=2" %%v in ('"%VENV_PYTHON%" --version 2^>^&1') do set VENV_VER=%%v
echo %VENV_VER% | findstr /b "3.12" >nul 2>&1
if errorlevel 1 (
    echo   [!!] .venv 版本不是 3.12，重新建立中...
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
echo   [!!] .venv 損壞，重新建立中...
rmdir /s /q "%VENV_DIR%"

:build_venv
echo   建立 .venv（使用 Python 3.12）...
"%VENV_BUILD%" -m venv "%VENV_DIR%"
if errorlevel 1 goto :venv_fail
"%VENV_PIP%" install --upgrade pip --quiet 2>nul

:install_pkgs
echo.
echo   安裝套件中（首次安裝需要數分鐘，請耐心等候）...
echo.
nvidia-smi >nul 2>&1
if not errorlevel 1 (
    echo   [OK] 偵測到 GPU，安裝 PyTorch CUDA 版本...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cu121
) else (
    echo   [--] 未偵測到 GPU，安裝 PyTorch CPU 版本...
    "%VENV_PIP%" install torch --index-url https://download.pytorch.org/whl/cpu
)
if errorlevel 1 goto :pkg_fail

echo   安裝 fastapi / uvicorn / faster-whisper...
"%VENV_PIP%" install fastapi "uvicorn[standard]" python-multipart faster-whisper
if errorlevel 1 goto :pkg_fail

echo.
echo   [OK] 所有套件安裝完成！
echo.

REM --- 4. 檢查 ffmpeg ---
:ffmpeg_check
ffmpeg -version >nul 2>&1
if not errorlevel 1 goto :start_server

echo   [!!] 找不到 ffmpeg，透過 winget 自動安裝中...
echo        （mp3、m4a、ogg 等格式需要 ffmpeg）
winget install Gyan.FFmpeg -e --silent --accept-package-agreements --accept-source-agreements >nul 2>&1

REM 安裝後再次確認
ffmpeg -version >nul 2>&1
if not errorlevel 1 (
    echo   [OK] ffmpeg 安裝完成
    goto :start_server
)

REM 確認已知安裝路徑
if exist "C:\Program Files\ffmpeg\bin\ffmpeg.exe" (
    echo   [OK] ffmpeg 就緒
    goto :start_server
)

echo   [--] ffmpeg 可能需要重新啟動後生效
echo        （wav / webm 格式無需 ffmpeg 仍可使用）

:start_server
if not exist "%~dp0server.py" goto :no_server

echo   [OK] 環境就緒
echo.
echo   啟動伺服器中...
echo   （首次執行會下載 Whisper 語音模型，需要數分鐘）
echo.
echo   瀏覽器將自動開啟。或手動前往：http://localhost:8000
echo.
echo ------------------------------------------------
echo   關閉此視窗即可停止伺服器
echo ------------------------------------------------
echo.

start /b powershell -WindowStyle Hidden -NonInteractive -Command "$i=0; while($i -lt 300){ Start-Sleep 3; try{ $r=Invoke-WebRequest 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop; if($r.StatusCode -eq 200){ Start-Process 'http://localhost:8000'; break } }catch{}; $i++ }"

cd /d "%~dp0"
"%VENV_PYTHON%" server.py

echo.
echo 伺服器已停止。
goto :end

REM --- 錯誤處理 ---
:install_python
echo   [!!] 找不到 Python，自動安裝中...
winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 goto :python_fail
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set PYTHON_CMD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set VENV_BUILD=%LOCALAPPDATA%\Programs\Python\Python312\python.exe
if "%PYTHON_CMD%"=="" goto :python_restart
goto :venv_check

:python_fail
echo.
echo [錯誤] 自動安裝失敗。
echo        請手動安裝 Python 3.12：
echo        https://www.python.org/downloads/release/python-3129/
goto :end

:python_restart
echo.
echo [OK] Python 3.12 安裝完成！請關閉此視窗後再次執行 start.bat。
goto :end

:no_py312
echo.
echo [錯誤] 無法安裝 Python 3.12。
echo        PyTorch 需要 Python 3.12 以下版本。
echo        請手動安裝：https://www.python.org/downloads/release/python-3129/
goto :end

:venv_fail
echo.
echo [錯誤] 建立 .venv 失敗。請嘗試以系統管理員身份執行。
goto :end

:pkg_fail
echo.
echo [錯誤] 套件安裝失敗。請確認網路連線後再試。
goto :end

:no_server
echo.
echo [錯誤] 找不到 server.py，請重新下載本程式。
goto :end

:end
echo.
pause
